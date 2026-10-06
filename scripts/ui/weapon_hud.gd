class_name WeaponHud
extends Control
## The gun in hand, top right: a pill of the weapon wheel's smoked glass (glass_hud.gdshader, the
## health bar's mode with no fill) holding the gun's silhouette (the wheel's own icons), its name,
## an infinity sign for the ammunition this game does not count, and one chip per slot with the
## equipped one lit. It pops when the gun changes. It replaced a line of plain text
## ("[1] AK-47   [2] Rocket Launcher   [3] Shotgun").
##
## Built in code by DebugHud; scales with the window height, like the stars under it.

## Panel size at 1080 lines (px) and its margin from the top right corner.
@export var panel_size: Vector2 = Vector2(360.0, 80.0)
@export var margin: float = 16.0
## How long the pop on a weapon change lasts (s) and how far the icon swells (fraction).
@export var pop_time: float = 0.28
@export var pop_scale: float = 0.12

const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"

var _glass: ColorRect
var _glass_mat: ShaderMaterial
var _ink: Control
var _font: Font
var _font_medium: Font
var _player: Node
var _shown: Weapon
var _pop: float = 0.0
var _scale: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = _load_font(FONT_SEMIBOLD)
	_font_medium = _load_font(FONT_MEDIUM)
	_glass = ColorRect.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = load("res://shaders/glass_hud.gdshader")
	_glass_mat.set_shader_parameter("mode", 1)
	_glass_mat.set_shader_parameter("bar_fill", 0.0)
	_glass.material = _glass_mat
	add_child(_glass)
	_ink = Control.new()
	_ink.name = "Ink"
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_ink)
	add_child(_ink)


## The panel's rect in viewport pixels (WantedHud hangs the stars under it).
func panel_rect() -> Rect2:
	return Rect2(_glass.position, _glass.size) if _glass else Rect2()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	var manager: Node = _player.get("weapon_manager") if _player else null
	var current: Weapon = manager.get("current") if manager else null
	# Real time: the wheel and the downed card slow the game clock.
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	if current != _shown:
		_pop = 1.0 if _shown != null else 0.0
		_shown = current
	_pop = move_toward(_pop, 0.0, dt / maxf(pop_time, 0.01))
	_layout()
	_glass.visible = current != null
	_ink.queue_redraw()


func _layout() -> void:
	var view := get_viewport_rect().size
	_scale = clampf(view.y / 1080.0, 0.7, 2.0)
	var size := (panel_size * _scale).round()
	var m := margin * _scale
	_glass.size = size
	_glass.position = Vector2(view.x - m - size.x, m).round()
	_glass_mat.set_shader_parameter("rect_px", size)
	_glass_mat.set_shader_parameter("bar_corner", size.y * 0.36)
	_ink.position = _glass.position
	_ink.size = size


func _draw_ink() -> void:
	if _shown == null or _player == null:
		return
	var manager: Node = _player.get("weapon_manager")
	var weapons: Array = manager.get("weapons") if manager else []
	var s := _scale
	var size := _ink.size
	var ink := Color(1, 1, 1, 0.97)
	var soft := Color(1, 1, 1, 0.62)
	# The gun, left, swelling a little on a change.
	var e := _pop * _pop
	var icon_w := 132.0 * s * (1.0 + pop_scale * e)
	WeaponWheel._draw_icon(_ink, WeaponWheel._icon_for(_shown), Vector2(22.0 * s + 66.0 * s, size.y * 0.5 + 1.0 * s), icon_w, ink)
	# A hairline between the gun and the words.
	var split_x := 176.0 * s
	_ink.draw_line(Vector2(split_x, size.y * 0.24), Vector2(split_x, size.y * 0.76), Color(1, 1, 1, 0.18), maxf(s, 1.0), true)
	# The name, right-aligned, small caps by way of upper case and tracking.
	var right := size.x - 22.0 * s
	var name_px := int(round(17.0 * s))
	var name := _shown.display_name.to_upper()
	var name_w := _tracked_width(_font, name, name_px, 1.2 * s)
	# A long name ("ROCKET LAUNCHER") shrinks to fit between the hairline and the edge.
	var room := right - (split_x + 14.0 * s)
	if name_w > room:
		name_px = maxi(7, int(floor(name_px * room / name_w)))
		name_w = _tracked_width(_font, name, name_px, 1.2 * s)
	_tracked(_font, name, Vector2(right - name_w, size.y * 0.42), name_px, 1.2 * s, ink)
	# One chip per slot, the equipped one lit, and the infinity sign before them.
	var chip := 17.0 * s
	var gap := 6.0 * s
	var n := weapons.size()
	var row_w := n * chip + maxf(n - 1, 0) * gap
	var y := size.y * 0.66
	var x0 := right - row_w
	for i in n:
		var r := Rect2(Vector2(x0 + i * (chip + gap), y - chip * 0.5), Vector2(chip, chip))
		var on: bool = weapons[i] == _shown
		var digit := str(i + 1)
		var dpx := int(round(11.0 * s))
		if on:
			_round_rect(r, chip * 0.28, Color(1, 1, 1, 0.95), true)
			_centred(_font, digit, r.get_center(), dpx, Color(0.06, 0.07, 0.09, 0.95))
		else:
			_round_rect(r, chip * 0.28, Color(1, 1, 1, 0.42), false)
			_centred(_font_medium, digit, r.get_center(), dpx, soft)
	var inf_px := int(round(22.0 * s))
	var inf_w := _font_medium.get_string_size("∞", HORIZONTAL_ALIGNMENT_LEFT, -1, inf_px).x
	_centred(_font_medium, "∞", Vector2(x0 - 10.0 * s - inf_w * 0.5, y + 0.5 * s), inf_px, soft)


func _round_rect(r: Rect2, radius: float, color: Color, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color if filled else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(int(round(radius)))
	sb.anti_aliasing = true
	if not filled:
		sb.border_color = color
		sb.set_border_width_all(maxi(1, int(round(_scale * 1.2))))
	_ink.draw_style_box(sb, r)


func _centred(font: Font, text: String, at: Vector2, px: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := Vector2(at.x - w * 0.5, at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06).round()
	_ink.draw_string(font, base + Vector2(0.0, maxf(px * 0.07, 1.0)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.3 * color.a))
	_ink.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _tracked_width(font: Font, text: String, px: int, track: float) -> float:
	var w := 0.0
	for c in text:
		w += font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
	return w - track


## `text` from `at` (left, vertically centred on the cap height) with `track` px between letters.
func _tracked(font: Font, text: String, at: Vector2, px: int, track: float, color: Color) -> void:
	var x := at.x
	var y := roundf(at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06)
	for c in text:
		var p := Vector2(round(x), y)
		_ink.draw_string(font, p + Vector2(0.0, maxf(px * 0.07, 1.0)), c, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.3 * color.a))
		_ink.draw_string(font, p, c, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		x += font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font
