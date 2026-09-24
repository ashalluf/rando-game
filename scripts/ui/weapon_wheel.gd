class_name WeaponWheel
extends CanvasLayer
## GTA-style weapon wheel in frosted glass (owner, 2026-09-24: "hold whatever button and it
## slows everything n lets u switch but i want the UI to look like apple glass style").
##
## Hold `weapon_wheel` (Tab opens it at once; the gamepad's left bumper opens it after
## `pad_hold_seconds`, and a shorter tap steps to the previous weapon instead). While it is up
## time eases down to `slow_time_scale` and the audio to `slow_audio_scale`, the mouse moves a
## virtual cursor (and the right stick points) at a segment, and letting go equips it; let go
## with the cursor still in the centre and you keep what you had. The camera does not turn and
## the gun does not fire meanwhile (`look_blocked` on the camera rig, `wheel_open` on the
## WeaponManager). Every way of closing it that is not a release - the pause menu, getting into
## a car, the node leaving the tree - puts time and audio straight back.
##
## Drawn in its own CanvasLayer above the HUD, so F1's HIDDEN mode does not hide it (it is
## gameplay, not overlay). The glass is `shaders/glass_ui.gdshader` on one rect; the icons and
## names are drawn on top in `_draw_content()`. All sizes follow the viewport height, and the
## wheel is only ever scaled while it animates, so it is pixel-crisp once open.

@export_group("Slow motion")
## Engine.time_scale while the wheel is open (1.0 = no slow motion).
@export_range(0.05, 1.0) var slow_time_scale: float = 0.25
## AudioServer.playback_speed_scale while the wheel is open (lower = deeper, slower sound).
@export_range(0.1, 1.0) var slow_audio_scale: float = 0.6
## Real seconds to ease into the slow motion, and back out of it.
@export var slow_ease_seconds: float = 0.15

@export_group("Opening")
## Real seconds for the wheel to fade and scale in (and out).
@export var fade_seconds: float = 0.12
## Scale the wheel grows from as it opens (1.0 = no zoom).
@export var open_from_scale: float = 0.92
## Gamepad: holding the bumper this long (real seconds) opens the wheel; a shorter tap steps to
## the previous weapon.
@export var pad_hold_seconds: float = 0.2
## Real seconds for a segment's highlight to come up or fade.
@export var hover_seconds: float = 0.08

@export_group("Selection")
## Mouse travel (pixels) that takes the cursor from the centre to the rim.
@export var mouse_travel_px: float = 160.0
## Cursor distance (fraction of the outer radius) below which a release keeps the current gun.
@export var dead_zone: float = 0.34
## Right stick deflection needed to point at a segment. Letting the stick spring back keeps
## the segment it last pointed at, so you can let go of the stick before the bumper.
@export var stick_dead_zone: float = 0.5

@export_group("Size")
## Outer radius of the ring, as a fraction of the viewport height.
@export var outer_radius: float = 0.3
## Inner radius of the ring.
@export var inner_radius: float = 0.158
## Radius of the glass disc in the middle.
@export var disc_radius: float = 0.118
## Gap between segments.
@export var gap: float = 0.011
## Corner rounding of the segments.
@export var corner_radius: float = 0.022
## How far the highlighted segment moves out, and how much it swells.
@export var hover_pop: float = 0.008
@export var hover_grow: float = 0.003
## Blur radius of the frosted glass.
@export var blur_radius: float = 0.016

@export_group("Text")
## Font sizes as fractions of the viewport height (clamped to stay legible when small).
@export var name_size: float = 0.022
@export var title_size: float = 0.031
@export var hint_size: float = 0.0155

const GLASS_SHADER := preload("res://shaders/glass_ui.gdshader")
const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
const MAX_SEGMENTS := 8

## Weapon silhouettes, pointing right, in a 100 x 40 box. Each entry is a list of shapes:
## a PackedVector2Array is a filled polygon; a Dictionary is {line, width} or {circle, r[, ring]}
## or {cut} (a polygon drawn dark, for a window through the body).
static var _icons: Dictionary = {}

var _root: Control
var _pivot: Control
var _glass: ColorRect
var _content: Control
var _mat: ShaderMaterial
var _font: Font
var _font_medium: Font

var _open: bool = false
var _pending_pad: bool = false
var _press_from_pad: bool = false
var _was_down: bool = false
var _used_pad: bool = false
var _press_time: float = 0.0
var _last_real: float = 0.0
## 0..1 how far open the wheel is drawn, and how far into the slow motion we are.
var _show: float = 0.0
var _slow: float = 0.0
## True while this node has changed the time or audio scale and not yet put it back.
var _owns_time: bool = false
var _applied_slow: float = 0.0
## Virtual cursor, in units of the outer radius, measured from the centre.
var _cursor: Vector2 = Vector2.ZERO
var _highlight: int = -1
var _hover := PackedFloat32Array()
var _player: Player
var _metrics: Dictionary = {}


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("weapon_wheel")
	_hover.resize(MAX_SEGMENTS)
	_font = _load_font(FONT_SEMIBOLD)
	_font_medium = _load_font(FONT_MEDIUM)
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_pivot = Control.new()
	_pivot.name = "Pivot"
	_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pivot)
	_mat = ShaderMaterial.new()
	_mat.shader = GLASS_SHADER
	_glass = ColorRect.new()
	_glass.name = "Glass"
	_glass.color = Color.WHITE
	_glass.material = _mat
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pivot.add_child(_glass)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.draw.connect(_draw_content)
	_pivot.add_child(_content)
	_root.visible = false
	_last_real = _now()


func _exit_tree() -> void:
	# Leaving the tree (scene reload, level freed) must never strand the game in slow motion.
	if _open or _pending_pad:
		_close(false)
	_restore_time()


func _input(event: InputEvent) -> void:
	if event.is_action("weapon_wheel") and event.is_pressed() and not event.is_echo():
		_press_from_pad = event is InputEventJoypadButton
	if not _open:
		return
	if event is InputEventMouseMotion:
		# Consumed here, so the camera (which reads _unhandled_input) does not turn.
		_move_cursor((event as InputEventMouseMotion).relative / maxf(mouse_travel_px, 1.0))
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now := _now()
	var dt := clampf(now - _last_real, 0.0, 0.1)
	_last_real = now
	var down := Input.is_action_pressed("weapon_wheel")
	if get_tree().paused:
		# The pause menu opened over us: shut without equipping and put time back at once.
		if _open or _pending_pad:
			_close(false)
		_was_down = down
		_show = 0.0
		_slow = 0.0
		_restore_time()
		_root.visible = false
		return
	if down and not _was_down:
		_on_press(now)
	elif _was_down and not down:
		_on_release()
	_was_down = down
	if _pending_pad and now - _press_time >= pad_hold_seconds:
		_pending_pad = false
		if _can_open():
			_open_wheel(true)
	if _open and not _can_open():
		_close(false)
	if _open:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length() > stick_dead_zone:
			_cursor = stick.normalized()
			_used_pad = true
		_highlight = _pointed()
	_animate(dt)


## True while the wheel is up (held and shown).
func is_open() -> bool:
	return _open


## The segment the cursor points at, or -1 in the centre dead zone (or with the wheel shut).
func highlighted() -> int:
	return _highlight if _open else -1


## Points the cursor at a segment (-1 = back to the centre). For tests and screenshots.
func point_at(index: int) -> void:
	var n := _segment_count()
	if index < 0 or n == 0:
		_cursor = Vector2.ZERO
	else:
		var a := float(index) * TAU / float(n)
		_cursor = Vector2(sin(a), -cos(a)) * 0.8
	_highlight = _pointed()


## Opens the wheel fully at once with `index` highlighted, time already slowed, no input
## needed: tools/glshot/still_shot.gd uses it (WHEEL=<index>) to photograph the wheel.
func show_for_shot(index: int) -> void:
	if not _can_open():
		return
	_open_wheel(false)
	point_at(index)
	_show = 1.0
	_slow = 1.0
	for k in MAX_SEGMENTS:
		_hover[k] = 1.0 if k == _highlight else 0.0
	_apply_time()
	_update_visuals()


func _on_press(now: float) -> void:
	var from_pad := _press_from_pad
	_press_from_pad = false
	if _open or not _can_open():
		return
	if from_pad:
		# Wait: a quick tap is "previous weapon", a hold is the wheel.
		_pending_pad = true
		_press_time = now
	else:
		_open_wheel(false)


func _on_release() -> void:
	if _pending_pad:
		_pending_pad = false
		var manager := _manager()
		if manager and _can_open():
			manager.equip(manager.current_index() - 1)
		return
	if _open:
		_close(true)


func _can_open() -> bool:
	var player := _get_player()
	return player != null and not player.is_driving() and _manager() != null \
			and not _manager().weapons.is_empty() and not get_tree().paused


func _open_wheel(from_pad: bool) -> void:
	_open = true
	_used_pad = from_pad
	_cursor = Vector2.ZERO
	_highlight = -1
	var manager := _manager()
	if manager:
		manager.wheel_open = true
	_block_look(true)


## Shuts the wheel; `equip` = a real release, which equips the highlighted segment.
func _close(equip: bool) -> void:
	var was_open := _open
	_open = false
	_pending_pad = false
	var manager := _manager()
	if manager:
		if equip and was_open and _highlight >= 0:
			manager.equip(_highlight)
		manager.wheel_open = false
	_block_look(false)
	# _highlight is kept for the fade-out, so the disc does not flick back to its idle hint.


func _block_look(blocked: bool) -> void:
	var player := _get_player()
	if player and player.camera_rig:
		# The rig grows this property in its own change; setting a missing one is a no-op.
		player.camera_rig.set("look_blocked", blocked)


func _move_cursor(delta: Vector2) -> void:
	_cursor += delta
	if _cursor.length() > 1.0:
		_cursor = _cursor.normalized()


func _pointed() -> int:
	var n := _segment_count()
	if n == 0 or _cursor.length() < dead_zone:
		return -1
	var a := atan2(_cursor.x, -_cursor.y) # clockwise from straight up
	return wrapi(int(floor(a / (TAU / float(n)) + 0.5)), 0, n)


# --- Time and animation -----------------------------------------------------------------

func _animate(dt: float) -> void:
	_show = move_toward(_show, 1.0 if _open else 0.0, dt / maxf(fade_seconds, 0.001))
	_slow = move_toward(_slow, 1.0 if _open else 0.0, dt / maxf(slow_ease_seconds, 0.001))
	var step := dt / maxf(hover_seconds, 0.001)
	for k in MAX_SEGMENTS:
		_hover[k] = move_toward(_hover[k], 1.0 if (_open and k == _highlight) else 0.0, step)
	_apply_time()
	_update_visuals()


## Writes the time and audio scale only when the eased value moves, so a tool that sets its own
## time scale while the wheel sits open (still_shot's freeze) is not overwritten every frame.
func _apply_time() -> void:
	if _slow <= 0.0:
		if _owns_time:
			_restore_time()
		return
	if _owns_time and is_equal_approx(_slow, _applied_slow):
		return
	var e := _slow * _slow * (3.0 - 2.0 * _slow)
	Engine.time_scale = lerpf(1.0, slow_time_scale, e)
	AudioServer.playback_speed_scale = lerpf(1.0, slow_audio_scale, e)
	_applied_slow = _slow
	_owns_time = true


func _restore_time() -> void:
	if not _owns_time:
		return
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_owns_time = false
	_applied_slow = 0.0


func _update_visuals() -> void:
	_root.visible = _show > 0.0
	if not _root.visible:
		return
	_layout()
	var e := 1.0 - pow(1.0 - _show, 3.0)
	_pivot.scale = Vector2.ONE * lerpf(open_from_scale, 1.0, e)
	_pivot.modulate.a = e
	_mat.set_shader_parameter("seg_hover", _hover)
	_content.queue_redraw()


## Sizes everything from the viewport height. Cheap enough to run every frame the wheel shows.
func _layout() -> void:
	var view := _root.get_viewport_rect().size
	var h := view.y
	var n := _segment_count()
	var m := {
		"h": h,
		"r_out": h * outer_radius,
		"r_in": h * inner_radius,
		"disc": h * disc_radius,
		"gap": maxf(h * gap, 4.0),
		"corner": h * corner_radius,
		"pop": h * hover_pop,
		"grow": h * hover_grow,
		"n": n,
	}
	if m == _metrics:
		return
	_metrics = m
	# Room for the glow and the shadow; whole pixels, so the text drawn inside lands on them.
	var half: float = ceilf(m.r_out + h * 0.06)
	_pivot.position = (view * 0.5).round()
	_glass.position = Vector2(-half, -half)
	_glass.size = Vector2(half, half) * 2.0
	_content.position = _glass.position
	_content.size = _glass.size
	_mat.set_shader_parameter("rect_px", _glass.size)
	_mat.set_shader_parameter("seg_count", n)
	_mat.set_shader_parameter("r_in", m.r_in)
	_mat.set_shader_parameter("r_out", m.r_out)
	_mat.set_shader_parameter("disc_r", m.disc)
	_mat.set_shader_parameter("gap", m.gap)
	_mat.set_shader_parameter("corner", m.corner)
	_mat.set_shader_parameter("pop", m.pop)
	_mat.set_shader_parameter("grow", m.grow)
	_mat.set_shader_parameter("blur_px", maxf(h * blur_radius, 6.0))
	_mat.set_shader_parameter("refract_px", h * 0.014)
	_mat.set_shader_parameter("bevel_px", h * 0.018)
	_mat.set_shader_parameter("rim_px", maxf(h * 0.0012, 1.2))
	_mat.set_shader_parameter("glow_px", h * 0.011)
	_mat.set_shader_parameter("shadow_offset", Vector2(0.0, h * 0.01))
	_mat.set_shader_parameter("shadow_px", h * 0.028)


# --- Drawing ----------------------------------------------------------------------------

func _draw_content() -> void:
	var manager := _manager()
	if manager == null or _metrics.is_empty():
		return
	var ci := _content
	var c := _content.size * 0.5
	var h: float = _metrics.h
	var n: int = _metrics.n
	var r_in: float = _metrics.r_in
	var r_out: float = _metrics.r_out
	var r_mid := (r_in + r_out) * 0.5
	var name_px := maxi(int(round(h * name_size)), 11)
	var title_px := maxi(int(round(h * title_size)), 15)
	var hint_px := maxi(int(round(h * hint_size)), 9)
	var step_a := TAU / float(maxi(n, 1))
	var chord := 2.0 * r_mid * sin(minf(step_a * 0.5, PI * 0.5))
	var icon_w := minf((r_out - r_in) * 1.12, chord * 0.62)
	for k in n:
		var weapon := manager.weapons[k]
		var hov := _hover[k]
		var dir := Vector2(sin(float(k) * step_a), -cos(float(k) * step_a))
		var at: Vector2 = c + dir * (r_mid + _metrics.pop * hov)
		var icon_at := at + Vector2(0.0, -name_px * 0.55)
		var ink := Color(1, 1, 1, 1).lerp(Color(0.86, 0.87, 0.9, 1.0), 1.0 - hov)
		_draw_icon(ci, _icon_for(weapon), icon_at, icon_w * lerpf(1.0, 1.04, hov), ink)
		var name_y := icon_at.y + icon_w * 0.2 + name_px * 1.25
		_text(ci, _font, weapon.display_name, Vector2(at.x, name_y), name_px, ink)
		if weapon == manager.current:
			# The equipped gun: a small dot under its name, the way a dock marks a running app.
			var dot := Vector2(at.x, name_y + name_px * 0.85)
			var dot_r := maxf(h * 0.0032, 2.0)
			ci.draw_circle(dot + Vector2(0.0, 1.0), dot_r + 0.5, Color(0, 0, 0, 0.2), true, -1.0, true)
			ci.draw_circle(dot, dot_r, Color(1, 1, 1, 0.95), true, -1.0, true)
	# The centre disc: the highlighted gun (or the one in hand) and what to do.
	var shown := manager.current
	if _highlight >= 0 and _highlight < manager.weapons.size():
		shown = manager.weapons[_highlight]
	var title := shown.display_name if shown else ""
	_text(ci, _font, title, c + Vector2(0.0, -hint_px * 0.35), title_px, Color.WHITE)
	var button := "LB" if _used_pad else "Tab"
	var hint := ("Release %s to equip" % button) if _highlight >= 0 else "Point at a weapon"
	_text(ci, _font_medium, hint, c + Vector2(0.0, title_px * 0.62 + hint_px * 0.5), hint_px, Color(1, 1, 1, 0.72))
	# Which way the cursor points: a short bright arc on the disc's edge.
	var reach := clampf((_cursor.length() - dead_zone * 0.6) / (dead_zone * 0.4), 0.0, 1.0)
	if reach > 0.0:
		var a := atan2(_cursor.y, _cursor.x)
		var r: float = _metrics.disc - maxf(h * 0.006, 3.0)
		ci.draw_arc(c, r, a - 0.22, a + 0.22, 16, Color(1, 1, 1, 0.85 * reach), maxf(h * 0.0035, 2.0), true)


## Text centred on `at` (horizontally, and on the cap height vertically), with a faint shadow.
func _text(ci: CanvasItem, font: Font, text: String, at: Vector2, px: int, color: Color) -> void:
	if text == "":
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := Vector2(at.x - w * 0.5, at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06)
	base = base.round()
	ci.draw_string(font, base + Vector2(0.0, maxf(px * 0.07, 1.0)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.28 * color.a))
	ci.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


## Draws an icon from the 100 x 40 box, `width` pixels wide, centred on `at`.
func _draw_icon(ci: CanvasItem, shapes: Array, at: Vector2, width: float, color: Color) -> void:
	var s := width / 100.0
	var origin := at - Vector2(50.0, 20.0) * s
	var shadow := Color(0, 0, 0, 0.22)
	var drop := Vector2(0.0, maxf(s * 1.1, 1.0))
	for pass_i in 2:
		var col := shadow if pass_i == 0 else color
		var off := drop if pass_i == 0 else Vector2.ZERO
		for shape in shapes:
			if shape is PackedVector2Array:
				var pts := PackedVector2Array()
				for q in (shape as PackedVector2Array):
					pts.append(origin + off + q * s)
				ci.draw_colored_polygon(pts, col)
				# An antialiased outline in the same colour gives the fill a soft edge.
				pts.append(pts[0])
				ci.draw_polyline(pts, col, 1.0, true)
			elif shape is Dictionary:
				var d := shape as Dictionary
				if d.has("line"):
					var pts := PackedVector2Array()
					for q in (d.line as PackedVector2Array):
						pts.append(origin + off + q * s)
					ci.draw_polyline(pts, col, maxf(float(d.width) * s, 1.0), true)
				elif d.has("circle"):
					var p: Vector2 = origin + off + (d.circle as Vector2) * s
					if d.get("ring", false):
						ci.draw_arc(p, float(d.r) * s, 0.0, TAU, 32, col, maxf(1.6 * s, 1.0), true)
					else:
						ci.draw_circle(p, float(d.r) * s, col, true, -1.0, true)
				elif d.has("cut") and pass_i == 1:
					var pts := PackedVector2Array()
					for q in (d.cut as PackedVector2Array):
						pts.append(origin + q * s)
					ci.draw_colored_polygon(pts, Color(0.05, 0.06, 0.08, 0.45))


func _icon_for(weapon: Weapon) -> Array:
	if _icons.is_empty():
		_build_icons()
	var key := ""
	if weapon.get_script():
		key = (weapon.get_script() as Script).get_global_name()
	return _icons.get(key, _icons["_default"])


static func _poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, points.size(), 2):
		out.append(Vector2(points[i], points[i + 1]))
	return out


static func _build_icons() -> void:
	# AK-47: angled wooden stock, receiver, backswept grip, curved magazine, handguard with the
	# gas tube above it, front sight post and a slant muzzle brake.
	_icons["AssaultRifle"] = [
		_poly([0, 14, 3, 13.4, 24, 11.8, 24, 18.6, 9, 23.2, 1.2, 26.6, 0, 26.2]),
		_poly([23, 11.4, 56, 11.4, 56, 18.6, 23, 18.6]),
		_poly([47.5, 9.4, 55, 9.4, 55, 11.6, 47.5, 11.6]),
		_poly([30, 18, 37, 18, 33.2, 28.4, 26.4, 27.2]),
		{"line": _poly([37.2, 18.4, 37.8, 21.8, 41.5, 22.8, 45.2, 21.2, 45.6, 18.4]), "width": 1.5},
		_poly([45.6, 18.2, 52.4, 18.2, 53.8, 23.2, 56, 28.2, 59, 32.6, 52.6, 36.4, 49.8, 31.6, 47.6, 26.6, 46.2, 22]),
		_poly([56, 13.2, 74.5, 13.6, 74.5, 18, 56, 18.4]),
		_poly([56, 9.8, 77.5, 10.4, 77.5, 12.5, 56, 12.5]),
		_poly([74, 13.8, 93, 13.8, 93, 16.2, 74, 16.2]),
		_poly([84, 9.2, 86.2, 9.2, 86.8, 13.9, 83.6, 13.9]),
		_poly([92.4, 12.6, 99, 13.2, 100, 16.8, 92.4, 16.8]),
		{"line": _poly([75, 17.6, 90, 17.6]), "width": 0.9},
	]
	# Rocket launcher: flared exhaust, long tube, optic on a mount, two grips and a pointed
	# warhead standing out of the muzzle.
	_icons["RocketLauncher"] = [
		_poly([0, 10.6, 9.5, 13.4, 9.5, 23, 0, 25.8]),
		_poly([9, 13.2, 66, 13.2, 66, 23.2, 9, 23.2]),
		_poly([67.5, 12.4, 76, 10.4, 84, 10.6, 99.5, 18.2, 84, 25.8, 76, 26, 67.5, 24]),
		_poly([29, 6.2, 46, 6.2, 47.5, 8, 47.5, 11.2, 29, 11.2]),
		_poly([35, 11, 41, 11, 41, 13.4, 35, 13.4]),
		_poly([25, 23, 31.5, 23, 30, 32.4, 23.6, 31.4]),
		{"line": _poly([31.5, 23.4, 32.6, 27.4, 37.5, 27.8, 38.4, 23.4]), "width": 1.4},
		_poly([45, 23, 51, 23, 49.6, 30.6, 44, 29.8]),
		_poly([14, 23, 21, 23, 20, 26, 15, 26]),
		{"line": _poly([56, 12.6, 56, 23.8]), "width": 1.0},
	]
	# Gravity gun: a chamfered hull with cooling fins, a rear grip, a centre emitter and two
	# curved claws around a glowing tip.
	_icons["GravityGun"] = [
		_poly([7, 14.5, 13.5, 10, 52, 10, 58.5, 13.5, 58.5, 24.5, 52, 28, 13.5, 28, 7, 23.5]),
		_poly([17, 27, 27, 27, 24.4, 37.6, 14.6, 36.4]),
		_poly([19, 6, 23.5, 6, 23.5, 10.4, 19, 10.4]),
		_poly([27, 6, 31.5, 6, 31.5, 10.4, 27, 10.4]),
		_poly([35, 6, 39.5, 6, 39.5, 10.4, 35, 10.4]),
		_poly([55, 12.4, 67, 6.6, 80, 5.4, 90.5, 9.6, 88.2, 12.2, 79, 9.8, 67.4, 12.4, 59, 16.6]),
		_poly([55, 25.6, 67, 31.4, 80, 32.6, 90.5, 28.4, 88.2, 25.8, 79, 28.2, 67.4, 25.6, 59, 21.4]),
		_poly([58, 16, 75, 16.6, 75, 21.4, 58, 22]),
		{"circle": Vector2(83, 19), "r": 3.2, "ring": true},
		{"circle": Vector2(83, 19), "r": 1.5},
		{"cut": _poly([30, 15, 48, 15, 50, 17, 50, 21, 48, 23, 30, 23, 28, 21, 28, 17])},
	]
	# Anything added later without an icon of its own: a plain pistol.
	_icons["_default"] = [
		_poly([30, 12, 72, 12, 72, 19, 30, 19]),
		_poly([33, 18, 44, 18, 40, 34, 29, 32]),
		{"line": _poly([44, 19, 45, 23.5, 51, 23.5, 52, 19]), "width": 1.5},
	]


# --- Lookups ----------------------------------------------------------------------------

func _get_player() -> Player:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	return _player


func _manager() -> WeaponManager:
	var player := _get_player()
	return player.weapon_manager if player else null


func _segment_count() -> int:
	var manager := _manager()
	return mini(manager.weapons.size(), MAX_SEGMENTS) if manager else 0


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font


static func _now() -> float:
	return Time.get_ticks_usec() * 0.000001
