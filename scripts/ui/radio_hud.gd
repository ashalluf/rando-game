class_name RadioHud
extends Control
## The car radio's station card (CarRadio): a pill of the HUD's smoked glass (glass_hud.gdshader,
## mode 1, like WeaponHud) at the top centre that slides down when the player tunes, gets into a
## car, or a new song starts, and fades away after CarRadio.card_seconds. It shows the frequency
## on a disc in the station's colour, the station's name and slogan, a dial of five pips (the four
## stations and OFF), a little spectrum bouncing while music plays, and the song now on air (or
## UP NEXT while the station's ident plays). Off, it says RADIO OFF.
##
## Built in code by DebugHud, so F1's HIDDEN mode hides it; scales with the window height.

## Card size at 1080 lines (px) and its gap from the top edge.
@export var panel_size: Vector2 = Vector2(560.0, 112.0)
@export var margin: float = 22.0
## Slide and fade in / out (real s).
@export var ease_in: float = 0.22
@export var ease_out: float = 0.5

const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"

var _glass: ColorRect
var _glass_mat: ShaderMaterial
var _ink: Control
var _font: Font
var _font_medium: Font
var _scale: float = 1.0
var _show: float = 0.0 # 0..1 on screen
var _t: float = 0.0
## Forces the card up whatever the radio says (stills): -2 = no force, else a station / OFF.
var force_station: int = -2


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
	_glass.visible = false
	_ink.visible = false


## True while the card is (even partly) on screen.
func showing() -> bool:
	return _show > 0.0


func _radio() -> CarRadio:
	return CarRadio.instance()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_t += dt
	var r := _radio()
	var want := false
	if force_station != -2:
		want = true
	elif r != null and r.car != null:
		var hold := r.card_seconds if r.card_kind == "tune" else r.card_seconds * 0.8
		want = r.card_age < hold
	_show = move_toward(_show, 1.0 if want else 0.0, dt / maxf(ease_in if want else ease_out, 0.01))
	var on := _show > 0.0
	_glass.visible = on
	_ink.visible = on
	if not on:
		return
	_layout()
	_ink.queue_redraw()


func _layout() -> void:
	var view := get_viewport_rect().size
	_scale = HudTheme.scale(view)
	var size := (panel_size * _scale).round()
	var e := 1.0 - pow(1.0 - _show, 3.0)
	var y := margin * _scale - (1.0 - e) * 26.0 * _scale
	_glass.size = size
	_glass.position = Vector2((view.x - size.x) * 0.5, y).round()
	_glass.modulate = Color(1, 1, 1, e)
	_glass_mat.set_shader_parameter("rect_px", size)
	_glass_mat.set_shader_parameter("bar_corner", size.y * 0.3)
	_ink.position = _glass.position
	_ink.size = size
	_ink.modulate = Color(1, 1, 1, e)


func _shown_station() -> int:
	if force_station != -2:
		return force_station
	var r := _radio()
	return r.station if r != null else CarRadio.OFF


func _draw_ink() -> void:
	var s := _scale
	var size := _ink.size
	var st := _shown_station()
	var ink := Color(1, 1, 1, 0.97)
	var soft := Color(1, 1, 1, 0.62)
	var faint := Color(1, 1, 1, 0.38)
	var on := st >= 0 and st < CarRadio.STATIONS.size()
	var info: Dictionary = CarRadio.STATIONS[st] if on else {}
	var accent: Color = info.color if on else Color(0.7, 0.72, 0.76)
	# The frequency disc, left.
	var c := Vector2(size.y * 0.5 + 6.0 * s, size.y * 0.5)
	var rad := size.y * 0.36
	_ink.draw_circle(c, rad + 2.0 * s, Color(accent.r, accent.g, accent.b, 0.25), true, -1.0, true)
	_ink.draw_circle(c, rad, Color(accent.r * 0.9, accent.g * 0.9, accent.b * 0.9, 0.92), true, -1.0, true)
	_ink.draw_arc(c, rad - 3.0 * s, 0.0, TAU, 48, Color(1, 1, 1, 0.35), maxf(s, 1.0), true)
	var dark := Color(0.05, 0.05, 0.07, 0.95)
	if on:
		_centred(_font, info.freq, c - Vector2(0.0, 6.0 * s), int(round(22.0 * s)), dark, false)
		_centred(_font_medium, "FM", c + Vector2(0.0, 15.0 * s), int(round(11.0 * s)), Color(dark.r, dark.g, dark.b, 0.75), false)
	else:
		_centred(_font, "OFF", c, int(round(18.0 * s)), dark, false)
	var x0 := c.x + rad + 20.0 * s
	var right := size.x - 22.0 * s
	# The name and slogan.
	var name: String = info.name if on else "RADIO OFF"
	_tracked(_font, name, Vector2(x0, size.y * 0.28), int(round(25.0 * s)), 2.2 * s, ink)
	var sub: String = ("%s  ·  %s" % [String(info.genre).to_upper(), info.slogan]) if on else "Scroll or press Q to tune"
	_text(_font_medium, sub, Vector2(x0, size.y * 0.52), int(round(13.0 * s)), soft, right - x0)
	# The dial: four stations and OFF.
	var n := CarRadio.STATIONS.size() + 1
	var pip := 7.0 * s
	var gap := 9.0 * s
	var dial_w := n * pip + (n - 1) * gap
	var dial_x := right - dial_w
	var dial_y := size.y * 0.28
	for i in n:
		var idx := i if i < CarRadio.STATIONS.size() else CarRadio.OFF
		var p := Vector2(dial_x + i * (pip + gap) + pip * 0.5, dial_y)
		if idx == st:
			_ink.draw_circle(p, pip * 0.62, Color(accent.r, accent.g, accent.b, 1.0), true, -1.0, true)
		else:
			_ink.draw_circle(p, pip * 0.42, faint, true, -1.0, true)
	# A hairline, then what is on air.
	var hy := size.y * 0.68
	_ink.draw_line(Vector2(x0, hy), Vector2(right, hy), Color(1, 1, 1, 0.14), maxf(s, 1.0), true)
	if not on:
		return
	var r := _radio()
	var np: Dictionary = r.now_playing() if r != null and r.station == st else {}
	if np.is_empty():
		var tr: Array = info.tracks[0]
		np = {"title": tr[1], "artist": tr[2], "upcoming": false}
	var label := "UP NEXT" if np.upcoming else "NOW PLAYING"
	var ly := size.y * 0.84
	var lpx := int(round(10.0 * s))
	var lw := _tracked_width(_font, label, lpx, 1.4 * s)
	# The spectrum, in the station's colour, bouncing while music plays.
	var bars := 5
	var bw := 3.0 * s
	var live := r != null and r.playing() and r.station == st
	for b in bars:
		var h := 0.35
		if live:
			h = 0.25 + 0.75 * absf(sin(_t * (5.0 + b * 1.7) + b * 1.3) * sin(_t * (2.3 + b * 0.9)))
		var bh := maxf(2.0 * s, 13.0 * s * h)
		_ink.draw_rect(Rect2(Vector2(x0 + b * (bw + 2.0 * s), ly + 6.5 * s - bh), Vector2(bw, bh)), Color(accent.r, accent.g, accent.b, 0.9))
	var lx := x0 + bars * (bw + 2.0 * s) + 8.0 * s
	_tracked(_font, label, Vector2(lx, ly), lpx, 1.4 * s, Color(accent.r, accent.g, accent.b, 0.95))
	var tx := lx + lw + 10.0 * s
	_text(_font_medium, "%s  —  %s" % [np.title, np.artist], Vector2(tx, ly), int(round(13.0 * s)), ink, right - tx)


func _text(font: Font, text: String, at: Vector2, px: int, color: Color, room: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if w > room and room > 0.0:
		px = maxi(7, int(floor(px * room / w)))
	var base := Vector2(at.x, at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06).round()
	_ink.draw_string(font, base + Vector2(0.0, maxf(px * 0.07, 1.0)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.3 * color.a))
	_ink.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _centred(font: Font, text: String, at: Vector2, px: int, color: Color, shadow: bool = true) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var base := Vector2(at.x - w * 0.5, at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06).round()
	if shadow:
		_ink.draw_string(font, base + Vector2(0.0, maxf(px * 0.07, 1.0)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.3 * color.a))
	_ink.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _tracked_width(font: Font, text: String, px: int, track: float) -> float:
	var w := 0.0
	for ch in text:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
	return w - track


func _tracked(font: Font, text: String, at: Vector2, px: int, track: float, color: Color) -> void:
	var x := at.x
	var y := roundf(at.y + (font.get_ascent(px) - font.get_descent(px)) * 0.5 - px * 0.06)
	for ch in text:
		var p := Vector2(round(x), y)
		_ink.draw_string(font, p + Vector2(0.0, maxf(px * 0.07, 1.0)), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.3 * color.a))
		_ink.draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track


func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f:
			return f
	return ThemeDB.fallback_font
