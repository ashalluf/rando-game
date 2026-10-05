class_name PhotoMode
extends CanvasLayer
## Photo mode (owner shares screenshots from his Mac, so this is how the game is shown off).
## `photo_mode` (P / right stick click) freezes the world - the tree paused like the pause menu,
## and Engine.time_scale 0, which also stops shader TIME (clouds, water, sway, grain hold their
## instant) - hides the HUD and hands the view to a free camera of its own: WASD / left stick to
## fly, hold right mouse (or the right stick) to look, Q / E or the triggers down and up, Z / C or
## the bumpers to roll, Shift faster, Alt slower, the mouse wheel (while looking) the speed. It
## stays within `max_radius` of the player, so the streamed city round him is what it shows.
##
## The panel on the right (glass, shaders/photo_panel.gdshader): field of view, roll, speed;
## depth of field (focus distance, aperture, focus on what the centre of the frame is on;
## Forward+ only - Compatibility has none, so the section is hidden there); exposure; the time of
## day; the weather; a filter (a colour grade written into the look LUT, Environment's
## adjustment_color_correction, plus its saturation: black and white is a grade); the lens
## vignette and film grain (CityStreamer's Vignette layer); letterbox frames; hide the player;
## TAKE PHOTO, which saves a PNG at the window's resolution to Pictures/Rando Game (user://photos
## if that cannot be written; on the web the browser downloads it) and toasts where it went.
## H (pad Y) hides the panel, F / Enter (pad A) takes the photo, Esc / P (pad B) leaves.
##
## Leaving puts everything back exactly as it was: the camera in force, Engine.time_scale, the
## pause, the hour, the weather (every field the pause menu's check restores), the grade, the
## vignette and grain, the player's visibility and every HUD layer. It is built by the pause
## menu beside itself in the city scene and never opens over the pause menu (a paused tree).

## Furthest the camera may go from the player (metres).
@export var max_radius: float = 140.0
## Flying speed at the speed slider's default (metres per real second).
@export var move_speed: float = 8.0
## Multiplier while Shift (pad: left stick click) is held, and while Alt is held.
@export var fast_factor: float = 4.0
@export var slow_factor: float = 0.25
## Radians per pixel of mouse movement while looking.
@export var mouse_sensitivity: float = 0.0022
## Radians per second at full right-stick deflection.
@export var stick_look_speed: float = 1.8
## Degrees per second of roll while Z / C (or a bumper) is held.
@export var roll_speed: float = 40.0
## How close to the ground the camera may go (metres above the street).
@export var ground_clearance: float = 0.35
## Seconds (real) the weather runs after a change into rain or a storm, so the drops fill the
## air before the world freezes again.
@export var weather_settle_seconds: float = 1.4
## Seconds the "saved" toast stays up.
@export var toast_seconds: float = 4.5

## Filters: name, saturation (times the scene's), per-channel gain, lift, contrast (an S-curve
## mix, negative flattens) and, optionally, neutral (the scene's warm curve made grey, for a true
## black and white; without it a saturation-0 grade keeps the look's warmth, which is Mono). Applied to the scene's own look LUT, so a grade is on top of the
## game's look, never instead of it.
const GRADES := [
	["Natural", 1.0, Color(1, 1, 1), Color(0, 0, 0), 0.0],
	["Golden", 1.06, Color(1.05, 1.0, 0.86), Color(0.012, 0.006, 0.0), 0.12],
	["Teal & orange", 1.12, Color(1.04, 0.99, 0.94), Color(-0.01, 0.012, 0.03), 0.22],
	["Vivid", 1.3, Color(1, 1, 1), Color(0, 0, 0), 0.3],
	["Faded film", 0.78, Color(0.97, 0.95, 0.9), Color(0.06, 0.055, 0.05), -0.25],
	["Noir", 0.0, Color(1, 1, 1), Color(-0.01, -0.01, -0.01), 0.55, true],
	["Mono", 0.0, Color(1, 1, 1), Color(0.015, 0.015, 0.015), 0.1],
]
## Weather chips map to Weather.State (0 clear .. 3 storm).
const WEATHERS := ["Clear", "Cloudy", "Rain", "Storm"]
## Frames: name and width / height (0 = none).
const FRAMES := [["None", 0.0], ["2.39 : 1", 2.39], ["1.85 : 1", 1.85], ["4 : 5", 0.8], ["1 : 1", 1.0]]
## Weather fields that leaving puts back (the pause menu's check restores the same set).
const WEATHER_KEYS := ["state", "_previous", "blend", "wetness", "drying", "_forced", "_timer"]
const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
## The panel's width in 1080-line pixels.
const PANEL_W := 452.0

## Where TAKE PHOTO writes (empty = Pictures/Rando Game, then user://photos). Tests set it.
var save_dir_override: String = ""
## The path (or file name, on the web) the last photo went to, "" if it failed.
var last_saved: String = ""

var camera: Camera3D
var _open: bool = false
var _prev_camera: Camera3D
var _prev_time_scale: float = 1.0
var _prev_paused: bool = false
var _prev_mouse: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _prev_hour: float = -1.0
var _prev_weather := {}
var _prev_weather_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _prev_env := {}
var _prev_vignette := {}
var _prev_player_visible: bool = true
var _hidden_layers: Array[CanvasLayer] = []

var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0
var _anchor := Vector3.ZERO
var _speed_scale: float = 1.0
var _looking: bool = false
var _last_real: int = 0
var _settle: float = 0.0
var _capturing: bool = false
var _toast_left: float = 0.0
var _flash: float = 0.0

var _dof_on: bool = false
var _focus: float = 12.0
var _fstop: float = 2.8
var _grade: int = 0
var _frame_aspect: float = 0.0
var _base_gradient: Gradient

var _root: Control
var _bars: Control
var _bar_a: ColorRect
var _bar_b: ColorRect
var _ui: Control
var _frame: Control
var _panel: ColorRect
var _panel_mat: ShaderMaterial
var _scroll: ScrollContainer
var _toast: Label
var _toast_box: PanelContainer
var _flash_rect: ColorRect
var _focus_box: Control
var _vignette_box: Control
var _hour_box: Control
var _weather_box: Control
var _sliders := {}
var _value_labels := {}
var _chip_groups := {}
var _semibold: Font
var _medium: Font


func _ready() -> void:
	name = "PhotoMode"
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	# After everything else each frame: the weapon wheel puts Engine.time_scale back to 1 every
	# frame the tree is paused, and the value left at the end of a frame is the next frame's.
	process_priority = 1000
	_semibold = _load_font(FONT_SEMIBOLD)
	_medium = _load_font(FONT_MEDIUM)
	_build()
	_root.visible = false


func _exit_tree() -> void:
	# A scene reload or quit must never leave the engine frozen.
	if _open:
		close()


func is_open() -> bool:
	return _open


## True when photo mode may open now: not over the pause menu (a paused tree), a camera to
## start from, not in the middle of a capture.
func can_open() -> bool:
	return not _open and not get_tree().paused and get_viewport().get_camera_3d() != null and not _loading()


## True while the loading screen (a CanvasLayer at 128) is up.
func _loading() -> bool:
	var scene := get_parent()
	if scene == null:
		return false
	for n in scene.find_children("*", "CanvasLayer", true, false):
		if (n as CanvasLayer).layer >= 128 and (n as CanvasLayer).visible:
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed("photo_mode") and not event.is_echo() and can_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if _capturing:
		get_viewport().set_input_as_handled()
		return
	if (event.is_action_pressed("photo_mode") or event.is_action_pressed("toggle_mouse")) and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_pressed():
		var jb := event as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_A:
				take_photo()
			JOY_BUTTON_B:
				close()
			JOY_BUTTON_Y:
				_ui.visible = not _ui.visible
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_H:
			_ui.visible = not _ui.visible
			get_viewport().set_input_as_handled()
		elif k == KEY_F or k == KEY_ENTER or k == KEY_KP_ENTER:
			take_photo()
			get_viewport().set_input_as_handled()
		elif k == KEY_R:
			_set_roll(0.0)
			get_viewport().set_input_as_handled()
		elif k == KEY_F1:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_looking(mb.pressed)
			get_viewport().set_input_as_handled()
		elif _looking and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var s: HSlider = _sliders["speed"]
			s.value *= 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and (_looking or not _ui.visible):
		var rel := (event as InputEventMouseMotion).relative
		_turn(-rel.x * mouse_sensitivity, -rel.y * mouse_sensitivity)
		get_viewport().set_input_as_handled()


func _set_looking(on: bool) -> void:
	_looking = on
	if _ui.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


# --- Open and close ------------------------------------------------------------------------

func open() -> void:
	if _open:
		return
	_prev_camera = get_viewport().get_camera_3d()
	if _prev_camera == null:
		return
	_open = true
	_prev_time_scale = Engine.time_scale
	_prev_paused = get_tree().paused
	_prev_mouse = Input.mouse_mode
	# The camera: the one in force, copied, with its own attributes (auto exposure and all), so
	# the depth of field and exposure here never touch the player's.
	camera = Camera3D.new()
	camera.name = "PhotoCamera"
	add_child(camera)
	camera.global_transform = _prev_camera.global_transform
	camera.fov = _prev_camera.fov
	camera.near = _prev_camera.near
	camera.far = _prev_camera.far
	camera.cull_mask = _prev_camera.cull_mask
	camera.environment = _prev_camera.environment
	# Compatibility has neither auto exposure nor depth of field (setting either only warns).
	var attrs: CameraAttributes = CameraAttributesPractical.new()
	if _prev_camera.attributes and dof_supported():
		attrs = _prev_camera.attributes.duplicate() as CameraAttributes
	camera.attributes = attrs
	camera.current = true
	var e := camera.global_transform.basis.get_euler(EULER_ORDER_YXZ)
	_yaw = e.y
	_pitch = clampf(e.x, -1.5, 1.5)
	_roll = 0.0
	var player := _player()
	_anchor = player.global_position if player else camera.global_position
	_speed_scale = 1.0
	_looking = false
	_settle = 0.0
	_toast_left = 0.0
	_flash = 0.0
	_last_real = Time.get_ticks_usec()

	get_tree().paused = true
	Engine.time_scale = 0.0
	_snapshot()
	_hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Fresh settings each time, from what is in force.
	_dof_on = false
	_focus = clampf(_center_distance(), 0.5, 800.0)
	_fstop = 2.8
	_grade = 0
	_frame_aspect = 0.0
	_sync_ui()
	_apply_focus()
	_apply_exposure()
	_layout()
	_ui.visible = true
	_root.visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	_capturing = false
	_restore()
	if camera:
		camera.current = false
		camera.queue_free()
		camera = null
	if _prev_camera and is_instance_valid(_prev_camera):
		_prev_camera.current = true
	_prev_camera = null
	_root.visible = false
	Engine.time_scale = _prev_time_scale
	get_tree().paused = _prev_paused
	# As the pause menu leaves it; on the web the browser only gives the mouse back after a click.
	Input.mouse_mode = _prev_mouse if OS.has_feature("web") else Input.MOUSE_MODE_CAPTURED


## Everything photo mode may change, as it is now.
func _snapshot() -> void:
	var day := _scene_node("DayNight")
	_prev_hour = float(day.get("hour")) if day else -1.0
	_prev_weather.clear()
	var weather := _scene_node("Weather")
	if weather:
		for key in WEATHER_KEYS:
			_prev_weather[key] = weather.get(key)
		_prev_weather_mode = weather.process_mode
	_prev_env.clear()
	var env := _environment()
	if env:
		for key in ["adjustment_enabled", "adjustment_saturation", "adjustment_color_correction"]:
			_prev_env[key] = env.get(key)
		var tex := env.adjustment_color_correction as GradientTexture1D
		_base_gradient = tex.gradient if tex else null
	_prev_vignette.clear()
	var vig := _vignette_material()
	if vig:
		for key in ["strength", "grain"]:
			_prev_vignette[key] = vig.get_shader_parameter(key)
	var player := _player()
	_prev_player_visible = player.visible if player else true


func _restore() -> void:
	var weather := _scene_node("Weather")
	if weather:
		weather.process_mode = _prev_weather_mode
		for key in _prev_weather:
			weather.set(key, _prev_weather[key])
		# Its globals and the street's wetness, as they were (the next frame does it again).
		if weather.has_method("_process"):
			weather.call("_process", 0.0)
	var day := _scene_node("DayNight")
	if day and _prev_hour >= 0.0:
		day.set("hour", _prev_hour)
		if day.has_method("_apply"):
			day.call("_apply")
	var env := _environment()
	if env:
		for key in _prev_env:
			env.set(key, _prev_env[key])
	var vig := _vignette_material()
	if vig:
		for key in _prev_vignette:
			vig.set_shader_parameter(key, _prev_vignette[key])
	var player := _player()
	if player:
		player.visible = _prev_player_visible
	for l in _hidden_layers:
		if is_instance_valid(l):
			l.visible = true
	_hidden_layers.clear()


## Hides every HUD layer of the scene (the HUD, the weapon wheel - a nested layer ignores its
## parent's visibility - the wanted stars ...). Layers under the 3D picture's grade (the
## vignette, the lens rain: layer < 0) are part of the photo and stay; the loading screen
## (128) is not ours.
func _hide_hud() -> void:
	_hidden_layers.clear()
	var scene := get_parent()
	if scene == null:
		return
	for n in scene.find_children("*", "CanvasLayer", true, false):
		var l := n as CanvasLayer
		if l == self or l.layer < 0 or l.layer >= 128 or not l.visible:
			continue
		l.visible = false
		_hidden_layers.append(l)


# --- Per frame -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _open:
		return
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_real) / 1_000_000.0, 0.0, 0.1)
	_last_real = now
	# Frozen, except while a weather change settles in.
	if _settle > 0.0:
		_settle -= dt
		Engine.time_scale = 1.0
		var day := _scene_node("DayNight")
		if day and day.has_method("_apply"):
			day.call("_apply")
		if _settle <= 0.0:
			var weather := _scene_node("Weather")
			if weather:
				weather.process_mode = _prev_weather_mode
	else:
		Engine.time_scale = 0.0
	if not _capturing:
		_fly(dt)
	_layout()
	if _toast_left > 0.0:
		_toast_left -= dt
		_toast_box.modulate.a = clampf(_toast_left / 0.6, 0.0, 1.0)
		_toast_box.visible = _toast_left > 0.0
	if _flash > 0.0:
		_flash = maxf(_flash - dt * 3.0, 0.0)
		_flash_rect.color.a = _flash * 0.85
		_flash_rect.visible = _flash > 0.0


func _fly(dt: float) -> void:
	if camera == null:
		return
	# Look: the right stick always; the mouse in _input.
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.12:
		_turn(-look.x * stick_look_speed * dt, -look.y * stick_look_speed * dt)
	var roll_in := 0.0
	if Input.is_physical_key_pressed(KEY_Z) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER):
		roll_in += 1.0
	if Input.is_physical_key_pressed(KEY_C) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER):
		roll_in -= 1.0
	if roll_in != 0.0:
		_set_roll(clampf(rad_to_deg(_roll) + roll_in * roll_speed * dt, -90.0, 90.0))
	# Move: along the view, flattened for WASD so W goes where you look but up / down is Q / E.
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := 0.0
	if Input.is_physical_key_pressed(KEY_E):
		up += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		up -= 1.0
	up += Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	var speed := move_speed * float((_sliders["speed"] as HSlider).value) / 8.0
	if Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK):
		speed *= fast_factor
	if Input.is_physical_key_pressed(KEY_ALT):
		speed *= slow_factor
	var heading := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)
	var move := heading * Vector3(stick.x, 0.0, stick.y) + Vector3.UP * up
	var pos := camera.global_position + move.limit_length(1.5) * speed * dt
	camera.global_position = _clamp_position(pos)
	_apply_rotation()


func _turn(dyaw: float, dpitch: float) -> void:
	_yaw = wrapf(_yaw + dyaw, -PI, PI)
	_pitch = clampf(_pitch + dpitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_apply_rotation()


func _apply_rotation() -> void:
	if camera:
		camera.global_basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _roll)


## Inside `max_radius` of the player and above the street.
func _clamp_position(pos: Vector3) -> Vector3:
	var off := pos - _anchor
	if off.length() > max_radius:
		pos = _anchor + off.limit_length(max_radius)
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("ground_height_at"):
		var g: float = city.call("ground_height_at", pos)
		pos.y = maxf(pos.y, g + ground_clearance)
	return pos


# --- Settings ------------------------------------------------------------------------------

func set_fov(v: float) -> void:
	if camera:
		camera.fov = clampf(v, 10.0, 120.0)
	_show_value("fov", "%d°" % int(round(v)))


func _set_roll(deg: float) -> void:
	_roll = deg_to_rad(deg)
	_apply_rotation()
	var s: HSlider = _sliders.get("roll")
	if s:
		s.set_value_no_signal(deg)
	_show_value("roll", "%d°" % int(round(deg)))


func set_dof(on: bool) -> void:
	_dof_on = on
	_apply_focus()
	_light_chips("dof", 1 if on else 0)


func set_focus(metres: float) -> void:
	_focus = clampf(metres, 0.3, 2000.0)
	var s: HSlider = _sliders.get("focus")
	if s:
		s.set_value_no_signal(_focus)
	_apply_focus()


func set_fstop(f: float) -> void:
	_fstop = clampf(f, 1.0, 32.0)
	_apply_focus()


## Focus on whatever the centre of the frame is on.
func autofocus() -> void:
	set_focus(_center_distance())
	if not _dof_on:
		set_dof(true)


## Godot's near and far blur round `_focus`: the sharp band widens with the f-number (about
## 3.5 % of the distance a stop), and the blur amount falls with it.
func _apply_focus() -> void:
	_show_value("focus", ("%.1f m" % _focus) if _focus < 20.0 else ("%d m" % int(round(_focus))))
	_show_value("aperture", "f/%s" % (("%.1f" % _fstop) if _fstop < 10.0 else str(int(round(_fstop)))))
	if camera == null:
		return
	var attrs := camera.attributes as CameraAttributesPractical
	if attrs == null or not dof_supported():
		return
	var w := _focus * 0.035 * _fstop
	attrs.dof_blur_far_enabled = _dof_on
	attrs.dof_blur_near_enabled = _dof_on
	attrs.dof_blur_far_distance = _focus + w
	attrs.dof_blur_far_transition = maxf(_focus * 0.6, 0.5)
	attrs.dof_blur_near_distance = maxf(_focus - w * 0.6, 0.05)
	attrs.dof_blur_near_transition = maxf((_focus - w * 0.6) * 0.8, 0.05)
	attrs.dof_blur_amount = clampf(0.35 / _fstop, 0.015, 0.25)


func set_exposure(ev: float) -> void:
	if camera and camera.attributes:
		camera.attributes.exposure_multiplier = pow(2.0, ev)
	_show_value("exposure", "%+.1f EV" % ev)


func _apply_exposure() -> void:
	set_exposure(float((_sliders["exposure"] as HSlider).value))


func set_hour(h: float) -> void:
	var day := _scene_node("DayNight")
	if day == null:
		return
	day.set("hour", fposmod(h, 24.0))
	if day.has_method("_apply"):
		day.call("_apply")
	_show_value("hour", String(day.call("clock_text")) if day.has_method("clock_text") else "%.1f" % h)


## Weather.State 0 clear .. 3 storm, held while photo mode is open and put back on leaving. Rain
## and storms run for a moment so the drops fill the air before the world freezes again.
func set_weather(s: int) -> void:
	var weather := _scene_node("Weather")
	if weather == null or not weather.has_method("force_state"):
		return
	weather.call("force_state", s)
	if weather.has_method("_process"):
		weather.call("_process", 0.0)
	var day := _scene_node("DayNight")
	if day and day.has_method("_apply"):
		day.call("_apply")
	if s >= 2:
		weather.process_mode = Node.PROCESS_MODE_ALWAYS
		_settle = weather_settle_seconds
	_light_chips("weather", s)


func set_grade(i: int) -> void:
	_grade = clampi(i, 0, GRADES.size() - 1)
	var env := _environment()
	if env and _prev_env.has("adjustment_saturation"):
		var g: Array = GRADES[_grade]
		env.adjustment_enabled = true
		env.adjustment_saturation = float(_prev_env["adjustment_saturation"]) * float(g[1])
		env.adjustment_color_correction = _prev_env["adjustment_color_correction"] if _grade == 0 \
				else grade_texture(_base_gradient, g[2], g[3], float(g[4]), g.size() > 5 and bool(g[5]))
	_light_chips("grade", _grade)


## The look LUT with a grade on top: each channel of the scene's own curve through a gain, a
## lift and an S-curve (negative `contrast` flattens toward mid grey).
static func grade_texture(base: Gradient, gain: Color, lift: Color, contrast: float, neutral: bool = false) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in 33:
		var x := i / 32.0
		var c := base.sample(x) if base else Color(x, x, x)
		if neutral:
			var m := (c.r + c.g + c.b) / 3.0
			c = Color(m, m, m)
		var out := Color(1, 1, 1, 1)
		for ch in 3:
			var cv: float = c[ch]
			var v: float = cv * float(gain[ch]) + float(lift[ch]) * (1.0 - cv)
			v = clampf(v, 0.0, 1.0)
			var s: float = v * v * (3.0 - 2.0 * v)
			v = lerpf(v, s, contrast) if contrast >= 0.0 else lerpf(v, 0.5, -contrast * 0.5)
			out[ch] = clampf(v, 0.0, 1.0)
		offsets.append(x)
		colors.append(out)
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 256
	return tex


func set_vignette(v: float) -> void:
	var m := _vignette_material()
	if m:
		m.set_shader_parameter("strength", v)
	_show_value("vignette", "%d %%" % int(round(v * 100.0)))


func set_grain(v: float) -> void:
	var m := _vignette_material()
	if m:
		m.set_shader_parameter("grain", v)
	_show_value("grain", "%d %%" % int(round(v / 0.12 * 100.0)))


func set_frame(i: int) -> void:
	_frame_aspect = float(FRAMES[clampi(i, 0, FRAMES.size() - 1)][1])
	_light_chips("frame", i)
	_layout()


func set_hide_player(on: bool) -> void:
	var player := _player()
	if player:
		player.visible = _prev_player_visible and not on
	_light_chips("player", 1 if on else 0)


# --- Taking the photo ----------------------------------------------------------------------

## Hides the panel for two frames, reads the window back and saves it.
func take_photo() -> void:
	if not _open or _capturing:
		return
	_capturing = true
	var panel_was := _ui.visible
	_ui.visible = false
	_toast_box.visible = false
	_flash_rect.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not _open:
		_capturing = false
		return
	var img: Image = null
	var tex := get_viewport().get_texture()
	if tex:
		img = tex.get_image()
	_ui.visible = panel_was
	_capturing = false
	last_saved = ""
	if img == null or img.is_empty():
		_show_toast("Could not read the frame back")
		return
	last_saved = save_image(img)
	_flash = 1.0
	_show_toast(("Saved  " + _pretty_path(last_saved)) if last_saved != "" else "Could not save the photo")


## Writes the PNG and returns where it went ("" on failure).
func save_image(img: Image) -> String:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var file := "rando_%s.png" % stamp
	if OS.has_feature("web") and save_dir_override == "":
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), file, "image/png")
		return "Downloads/" + file
	var dirs: Array[String] = []
	if save_dir_override != "":
		dirs.append(save_dir_override)
	else:
		var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if pictures != "":
			dirs.append(pictures.path_join("Rando Game"))
		dirs.append("user://photos")
	for d in dirs:
		if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
			continue
		var path := d.path_join(file)
		var n := 2
		while FileAccess.file_exists(path):
			path = d.path_join("rando_%s_%d.png" % [stamp, n])
			n += 1
		if img.save_png(path) == OK:
			return ProjectSettings.globalize_path(path)
	return ""


func _pretty_path(p: String) -> String:
	var home := OS.get_environment("HOME")
	if home != "" and p.begins_with(home):
		return "~" + p.substr(home.length())
	return p


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast_box.visible = true
	_toast_box.modulate.a = 1.0
	_toast_left = toast_seconds


# --- Helpers -------------------------------------------------------------------------------

func _scene_node(n: String) -> Node:
	var scene := get_parent()
	return scene.get_node_or_null(n) if scene else null


func _environment() -> Environment:
	var we := _scene_node("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		return we.environment
	return get_viewport().world_3d.environment if get_viewport().world_3d else null


func _vignette_material() -> ShaderMaterial:
	var city := get_tree().get_first_node_in_group("city")
	var layer := city.get_node_or_null("Vignette") if city else null
	if layer == null or layer.get_child_count() == 0:
		return null
	return (layer.get_child(0) as CanvasItem).material as ShaderMaterial


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


## Metres to what the centre of the frame is on (60 when it is the sky).
func _center_distance() -> float:
	var cam := camera if camera else get_viewport().get_camera_3d()
	if cam == null or cam.get_world_3d() == null:
		return 12.0
	var from := cam.global_position
	var to := from - cam.global_basis.z * 2000.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# The player too: a shot of the hero focuses on the hero.
	q.collision_mask = 1 | 2 | 4 | 8
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	return from.distance_to(hit.position) if not hit.is_empty() else 60.0


static func dof_supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility" and not OS.has_feature("web") \
			and DisplayServer.get_name() != "headless"


# --- Layout --------------------------------------------------------------------------------

func _layout() -> void:
	var view := _root.get_viewport_rect().size if _root.is_inside_tree() else Vector2(1920, 1080)
	var s := clampf(view.y / 1080.0, 0.6, 3.0)
	_frame.scale = Vector2(s, s)
	_frame.size = view / s
	var h := _frame.size.y - 64.0
	_panel.position = Vector2(_frame.size.x - PANEL_W - 32.0, 32.0)
	_panel.size = Vector2(PANEL_W, h)
	_panel_mat.set_shader_parameter("rect_size", _panel.size)
	_scroll.position = _panel.position + Vector2(26.0, 22.0)
	_scroll.size = _panel.size - Vector2(40.0, 44.0)
	_toast_box.position = Vector2((_frame.size.x - PANEL_W - 32.0 - _toast_box.size.x) * 0.5, _frame.size.y - 120.0)
	# Letterbox bars in real pixels.
	if _frame_aspect <= 0.0:
		_bar_a.visible = false
		_bar_b.visible = false
		return
	_bar_a.visible = true
	_bar_b.visible = true
	var aspect := view.x / maxf(view.y, 1.0)
	if _frame_aspect >= aspect:
		var bar := (view.y - view.x / _frame_aspect) * 0.5
		_bar_a.position = Vector2.ZERO
		_bar_a.size = Vector2(view.x, bar)
		_bar_b.position = Vector2(0.0, view.y - bar)
		_bar_b.size = Vector2(view.x, bar)
	else:
		var bar := (view.x - view.y * _frame_aspect) * 0.5
		_bar_a.position = Vector2.ZERO
		_bar_a.size = Vector2(bar, view.y)
		_bar_b.position = Vector2(view.x - bar, 0.0)
		_bar_b.size = Vector2(bar, view.y)


func _sync_ui() -> void:
	(_sliders["fov"] as HSlider).set_value_no_signal(camera.fov if camera else 75.0)
	set_fov(camera.fov if camera else 75.0)
	_set_roll(0.0)
	(_sliders["speed"] as HSlider).set_value_no_signal(8.0)
	_show_value("speed", "8 m/s")
	(_sliders["focus"] as HSlider).set_value_no_signal(_focus)
	(_sliders["aperture"] as HSlider).set_value_no_signal(_fstop)
	_light_chips("dof", 0)
	(_sliders["exposure"] as HSlider).set_value_no_signal(0.0)
	var day := _scene_node("DayNight")
	if day:
		(_sliders["hour"] as HSlider).set_value_no_signal(float(day.get("hour")))
		_show_value("hour", String(day.call("clock_text")))
	_hour_box.visible = day != null
	var weather := _scene_node("Weather")
	_weather_box.visible = weather != null
	_light_chips("weather", int(weather.get("state")) if weather else -1)
	_light_chips("grade", 0)
	_light_chips("frame", 0)
	_light_chips("player", 0)
	var vig := _vignette_material()
	_vignette_box.visible = vig != null
	if vig:
		var v: float = float(vig.get_shader_parameter("strength"))
		var g: float = float(vig.get_shader_parameter("grain"))
		(_sliders["vignette"] as HSlider).set_value_no_signal(v)
		(_sliders["grain"] as HSlider).set_value_no_signal(g)
		_show_value("vignette", "%d %%" % int(round(v * 100.0)))
		_show_value("grain", "%d %%" % int(round(g / 0.12 * 100.0)))
	_focus_box.visible = dof_supported()


func _show_value(key: String, text: String) -> void:
	var l: Label = _value_labels.get(key)
	if l:
		l.text = text


func _light_chips(key: String, index: int) -> void:
	var chips: Array = _chip_groups.get(key, [])
	for i in chips.size():
		(chips[i] as Button).set_pressed_no_signal(i == index)


# --- Building ------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Letterbox bars (part of the photo) and the shutter flash.
	_bars = Control.new()
	_bars.name = "Bars"
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bars)
	_bar_a = _black_bar()
	_bar_b = _black_bar()
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.visible = false
	_root.add_child(_flash_rect)

	_ui = Control.new()
	_ui.name = "UI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ui)
	_frame = Control.new()
	_frame.name = "Frame"
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.theme = _theme()
	_ui.add_child(_frame)

	_panel = ColorRect.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_mat = ShaderMaterial.new()
	_panel_mat.shader = load("res://shaders/photo_panel.gdshader")
	_panel.material = _panel_mat
	_frame.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(_scroll)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W - 64.0, 0.0)
	col.add_theme_constant_override("separation", 7)
	_scroll.add_child(col)

	col.add_child(_label("PHOTO MODE", _semibold, 30, Color.WHITE, 4.0))
	col.add_child(_hint("Hold right mouse to look   ·   WASD  Q / E  to fly   ·   Shift faster"))
	col.add_child(_spacer(6.0))
	var shoot := _big_button("Take photo")
	shoot.pressed.connect(take_photo)
	col.add_child(shoot)
	col.add_child(_spacer(4.0))

	col.add_child(_section("CAMERA"))
	col.add_child(_slider("fov", "Field of view", 15.0, 110.0, 1.0, false, set_fov))
	col.add_child(_slider("roll", "Roll", -45.0, 45.0, 0.5, false, _set_roll))
	col.add_child(_slider("speed", "Speed", 1.0, 60.0, 0.5, true,
		func(v: float): _show_value("speed", "%d m/s" % int(round(v)))))

	_focus_box = VBoxContainer.new()
	(_focus_box as VBoxContainer).add_theme_constant_override("separation", 7)
	col.add_child(_focus_box)
	_focus_box.add_child(_spacer(4.0))
	_focus_box.add_child(_section("DEPTH OF FIELD"))
	var dof_row := _chips("dof", ["Off", "On"], func(i: int): set_dof(i == 1))
	var af := _chip("Focus on centre", false)
	af.pressed.connect(autofocus)
	dof_row.add_child(af)
	_focus_box.add_child(dof_row)
	_focus_box.add_child(_slider("focus", "Focus distance", 0.5, 800.0, 0.1, true, set_focus))
	_focus_box.add_child(_slider("aperture", "Aperture", 1.4, 22.0, 0.1, true, set_fstop))

	col.add_child(_spacer(4.0))
	col.add_child(_section("LIGHT"))
	col.add_child(_slider("exposure", "Exposure", -3.0, 3.0, 0.1, false, set_exposure))
	_hour_box = _slider("hour", "Time of day", 0.0, 23.99, 0.05, false, set_hour)
	col.add_child(_hour_box)
	_weather_box = _chips("weather", WEATHERS, set_weather)
	col.add_child(_weather_box)

	col.add_child(_spacer(4.0))
	col.add_child(_section("FILTER"))
	var names: Array = []
	for g: Array in GRADES:
		names.append(g[0])
	col.add_child(_chips("grade", names.slice(0, 4), set_grade))
	var more := _chips("grade_more", names.slice(4), func(i: int): set_grade(i + 4))
	col.add_child(more)
	# One group across both rows.
	_chip_groups["grade"] = (_chip_groups["grade"] as Array) + (_chip_groups["grade_more"] as Array)
	_vignette_box = VBoxContainer.new()
	(_vignette_box as VBoxContainer).add_theme_constant_override("separation", 7)
	col.add_child(_vignette_box)
	_vignette_box.add_child(_slider("vignette", "Vignette", 0.0, 1.0, 0.01, false, set_vignette))
	_vignette_box.add_child(_slider("grain", "Film grain", 0.0, 0.12, 0.002, false, set_grain))

	col.add_child(_spacer(4.0))
	col.add_child(_section("FRAME"))
	var frame_names: Array = []
	for f: Array in FRAMES:
		frame_names.append(f[0])
	col.add_child(_chips("frame", frame_names, set_frame))
	col.add_child(_chips("player", ["Show player", "Hide player"], func(i: int): set_hide_player(i == 1)))

	col.add_child(_spacer(10.0))
	var leave := _big_button("Leave photo mode")
	leave.pressed.connect(close)
	col.add_child(leave)
	col.add_child(_hint("F / Enter  photo   ·   H  hide panel   ·   Z / C  roll   ·   Esc  leave"))

	_toast_box = PanelContainer.new()
	_toast_box.name = "Toast"
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.035, 0.05, 0.72)
	sb.border_color = Color(1, 1, 1, 0.16)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	sb.anti_aliasing = true
	_toast_box.add_theme_stylebox_override("panel", sb)
	_toast = _label("", _medium, 17, Color.WHITE, 0.3)
	_toast_box.add_child(_toast)
	_toast_box.visible = false
	# Laid out in the scaled frame's units, like the panel.
	_frame.add_child(_toast_box)


func _black_bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color.BLACK
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	_bars.add_child(r)
	return r


func _slider(key: String, text: String, lo: float, hi: float, step: float, exp_edit: bool, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_child(_label(text, _medium, 15, Color(1, 1, 1, 0.82), 0.2))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var value := _label("", _semibold, 15, Color(1, 1, 1, 0.6), 0.5)
	head.add_child(value)
	box.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.exp_edit = exp_edit
	s.custom_minimum_size = Vector2(0.0, 26.0)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(on_change)
	box.add_child(s)
	_sliders[key] = s
	_value_labels[key] = value
	return box


func _chips(key: String, labels: Array, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	var list: Array = []
	for i in labels.size():
		var b := _chip(String(labels[i]), true)
		b.button_group = group
		var idx := i
		b.pressed.connect(func(): on_pick.call(idx))
		row.add_child(b)
		list.append(b)
	_chip_groups[key] = list
	return row


func _theme() -> Theme:
	var t := Theme.new()
	t.default_font = _medium
	t.default_font_size = 16
	var empty := StyleBoxEmpty.new()
	t.set_stylebox("normal", "Button", _pill(Color(1, 1, 1, 0.08)))
	t.set_stylebox("hover", "Button", _pill(Color(1, 1, 1, 0.18)))
	t.set_stylebox("pressed", "Button", _pill(Color(1, 1, 1, 0.94)))
	t.set_stylebox("hover_pressed", "Button", _pill(Color(1, 1, 1, 1.0)))
	t.set_stylebox("focus", "Button", empty)
	t.set_color("font_color", "Button", Color(1, 1, 1, 0.9))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_hover_pressed_color", "Button", Color(0.06, 0.07, 0.09))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_font("font", "Button", _semibold)
	t.set_font_size("font_size", "Button", 14)
	# Sliders: a hairline track, filled white to the grabber, a white dot.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.16)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	t.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color(1, 1, 1, 0.8)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var dot := _dot_texture(18, 1.0)
	t.set_icon("grabber", "HSlider", dot)
	t.set_icon("grabber_highlight", "HSlider", dot)
	t.set_icon("grabber_disabled", "HSlider", _dot_texture(18, 0.4))
	# A slim scroll bar.
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(1, 1, 1, 0.0)
	bar.content_margin_left = 3.0
	bar.content_margin_right = 3.0
	t.set_stylebox("scroll", "VScrollBar", bar)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(1, 1, 1, 0.22)
	grab.set_corner_radius_all(3)
	grab.content_margin_left = 3.0
	grab.content_margin_right = 3.0
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	return t


## A soft white disc for the slider grabber.
static func _dot_texture(px: int, alpha: float) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r := px * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - 1.5 - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * alpha))
	return ImageTexture.create_from_image(img)


func _pill(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 11.0
	sb.content_margin_right = 11.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	sb.anti_aliasing = true
	return sb


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 50.0)
	b.add_theme_font_size_override("font_size", 19)
	var normal := _pill(Color(1, 1, 1, 0.9))
	var hover := _pill(Color(1, 1, 1, 1.0))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.07, 0.09))
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.07, 0.09))
	b.focus_mode = Control.FOCUS_NONE
	return b


func _chip(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(0.0, 36.0)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _hint(text: String) -> Label:
	var l := _label(text, _medium, 13, Color(1, 1, 1, 0.48), 0.2)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 64.0, 0.0)
	return l


func _section(text: String) -> Label:
	return _label(text, _semibold, 13, Color(1, 1, 1, 0.5), 3.0)


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
