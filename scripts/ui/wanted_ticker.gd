class_name WantedTicker
extends Control
## The line under the wanted stars when a level is reached (WantedEscalation.CALLS): what the
## new star brings - "AIR SUPPORT · ROADBLOCKS", "BASIN DEFENSE CORPS MOBILIZED" - for a few
## seconds, right-aligned under the stars, with a red and blue tick flashing beside it. A child of
## WantedHud (one line in its _ready); off with WantedEscalation (the A/B).

const HOLD := 3.2
const FADE_IN := 0.18
const FADE_OUT := 0.6
## Text size at 1080 lines (px).
const SIZE := 17.0

var _text: String = ""
var _age: float = 99.0
var _last: int = 0
var _police: Node
## The call shown last (tests read it).
var shown: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if not WantedEscalation.enabled:
		return
	if _police == null or not is_instance_valid(_police):
		_police = get_tree().get_first_node_in_group("wanted")
	var stars := int(_police.get("stars")) if _police else 0
	if stars > _last:
		_text = WantedEscalation.call_for(stars)
		shown = _text
		_age = 0.0
	_last = stars
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	var was := _age < HOLD + FADE_IN + FADE_OUT
	_age += dt
	if was or _age < HOLD + FADE_IN + FADE_OUT:
		queue_redraw()


func _draw() -> void:
	var a := HudTheme.envelope(_age, FADE_IN, HOLD, FADE_OUT)
	if a <= 0.001 or _text.is_empty():
		return
	var stars := get_parent().get_node_or_null("Stars") as Control
	if stars == null or not stars.visible:
		return
	var view := get_viewport_rect().size
	var k := HudTheme.scale(view)
	var px := int(roundf(SIZE * k))
	var f := HudTheme.display_bold()
	var right := stars.position.x + stars.size.x - 10.0
	var base := stars.position.y + stars.size.y + px * 1.05
	var w := HudTheme.tracked_width(f, _text, px, 1.6)
	# A soft dark plate so the line reads over a bright sky.
	draw_rect(Rect2(right - w - px * 1.4, base - px * 1.0, w + px * 1.6, px * 1.35), Color(0, 0, 0, 0.32 * a))
	HudTheme.draw_tracked_right(self, f, _text, right, base, px, 1.6, Color(1, 1, 1, 0.95 * a))
	var red := fmod(Time.get_ticks_msec() / 1000.0 * 3.0, 1.0) < 0.5
	var tick := Color(1.0, 0.16, 0.12, a) if red else Color(0.2, 0.42, 1.0, a)
	draw_rect(Rect2(right - w - px * 1.1, base - px * 0.72, px * 0.38, px * 0.62), tick)
