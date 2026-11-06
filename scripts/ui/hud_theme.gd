class_name HudTheme
extends RefCounted
## What every HUD piece shares (docs/HANDOFF.md "HUD polish"): the type, the 1080-line scale,
## the safe area, the ink colours and the easing curves.
##
## Type: Barlow Condensed (OFL) for display lines - district names, the vehicle's name, the
## speed - and Inter (OFL) for everything read at a glance below them. Both bundled under
## assets/fonts/ (docs/ASSETS.md); a missing file falls back to Godot's own font.
##
## The safe area: every corner piece sits `MARGIN` 1080-line units in from the edges (a TV's
## title-safe band is 3.5-5 % of the height; 40 / 1080 is 3.7 %), and on a window wider than
## `MAX_ASPECT` (21:9) the HUD is held to a centred 21:9 band, so on a 32:9 monitor the minimap
## does not sit in the far corner of the player's peripheral vision. 16:9 and 16:10 use the whole
## width. Everything is laid out in 1080-line units and scaled by `scale()`.

const FONT_DISPLAY := "res://assets/fonts/BarlowCondensed-SemiBold.woff2"
const FONT_DISPLAY_BOLD := "res://assets/fonts/BarlowCondensed-Bold.woff2"
const FONT_TEXT := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_TEXT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"

## The corner margin in 1080-line units.
const MARGIN := 40.0
## The widest the HUD's band may be (width / height); wider windows centre a band this wide.
const MAX_ASPECT := 21.0 / 9.0

## Ink: white text, its softer and fainter tiers, the warm accent (an original amber, used for
## underlines and the speed's needle) and the shadow under text.
const INK := Color(1.0, 1.0, 1.0, 0.97)
const SOFT := Color(1.0, 1.0, 1.0, 0.66)
const FAINT := Color(1.0, 1.0, 1.0, 0.38)
const ACCENT := Color(1.0, 0.72, 0.28, 1.0)
const SHADOW := Color(0.0, 0.0, 0.0, 0.55)

static var _fonts: Dictionary = {}


## The HUD's scale for a viewport this size: 1 at 1080 lines (MinimapFrame.hud_scale's rule,
## the settings' HUD size included).
static func scale(view: Vector2) -> float:
	return clampf(view.y / 1080.0, 0.7, 2.0) * GameSettings.hud_scale


## The rect the HUD's corner pieces keep inside, in viewport pixels.
static func safe_rect(view: Vector2) -> Rect2:
	var band := minf(view.x, view.y * MAX_ASPECT)
	var x0 := (view.x - band) * 0.5
	var m := MARGIN * scale(view)
	return Rect2(x0 + m, m, band - 2.0 * m, view.y - 2.0 * m)


## The horizontal inset an ultrawide window adds on each side (0 up to 21:9).
static func band_inset(view: Vector2) -> float:
	return maxf(0.0, (view.x - view.y * MAX_ASPECT) * 0.5)


static func font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[path] = f
	return f


static func display() -> Font:
	return font(FONT_DISPLAY)


static func display_bold() -> Font:
	return font(FONT_DISPLAY_BOLD)


static func text() -> Font:
	return font(FONT_TEXT)


static func text_medium() -> Font:
	return font(FONT_TEXT_MEDIUM)


## Easing, 0..1 in and out.
static func ease_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)


static func ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5


## A slight overshoot for things that pop in (the back easing, `k` the overshoot).
static func ease_back(t: float, k: float = 1.4) -> float:
	t = clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (k + 1.0) * t * t * t + k * t * t


## The in, hold, out envelope of a toast at `age` seconds: 0..1, eased both ways.
static func envelope(age: float, fade_in: float, hold: float, fade_out: float) -> float:
	if age < 0.0:
		return 0.0
	if age < fade_in:
		return ease_out(age / maxf(fade_in, 0.001))
	if age < fade_in + hold:
		return 1.0
	return 1.0 - ease_in_out((age - fade_in - hold) / maxf(fade_out, 0.001))


## Width of `s` with `track` px between letters.
static func tracked_width(f: Font, s: String, px: int, track: float) -> float:
	var w := 0.0
	for c in s:
		w += f.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track
	return maxf(w - track, 0.0)


## Draws `s` on `ci` from `at` (left end of the baseline) with letter tracking and a soft
## shadow under it (two offsets: it reads over a white sky and a black street alike).
static func draw_tracked(ci: CanvasItem, f: Font, s: String, at: Vector2, px: int, track: float, color: Color) -> void:
	var x := at.x
	var sh := maxf(px * 0.06, 1.0)
	for c in s:
		var p := Vector2(roundf(x), roundf(at.y))
		ci.draw_string(f, p + Vector2(0.0, sh), c, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(SHADOW.r, SHADOW.g, SHADOW.b, SHADOW.a * color.a))
		ci.draw_string(f, p + Vector2(sh * 0.5, sh * 1.8), c, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.18 * color.a))
		ci.draw_string(f, p, c, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)
		x += f.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + track


## Draws a run of tracked text right-aligned on `right`.
static func draw_tracked_right(ci: CanvasItem, f: Font, s: String, right: float, baseline: float, px: int, track: float, color: Color) -> void:
	draw_tracked(ci, f, s, Vector2(right - tracked_width(f, s, px, track), baseline), px, track, color)


## A glass material on glass_hud.gdshader's pill (mode 1, no fill): the panels' one look.
static func glass_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/glass_hud.gdshader")
	m.set_shader_parameter("mode", 1)
	m.set_shader_parameter("bar_fill", 0.0)
	return m
