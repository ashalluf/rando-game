class_name AreaToast
extends Control
## The place-name toast (docs/HANDOFF.md "HUD polish"): when the player comes into a new
## district - or a named place, or open country - its name rises in the bottom-left of the safe
## area in Barlow Condensed with the street under it in Inter, holds a few seconds and eases
## away. Changing street inside the same district shows the street alone, smaller, and not more
## often than every `street_gap` seconds. Built by DebugHud; CLEAN and FULL modes.
##
## The place is CityStreamer.district_name_at() (the coast towns, the zones, the districts); the
## street is `street_at()`: the nearest grid road whose carriageway the player is on or beside
## (CityPlan.road_name), none in a block's middle or off the grid. Nothing new is rolled.

## Seconds: ease in, hold, ease out of a district toast; a street toast holds `street_hold`.
@export var fade_in: float = 0.55
@export var hold: float = 3.6
@export var fade_out: float = 0.9
@export var street_hold: float = 2.4
## How long a new district must hold before it is announced (a kerb on a boundary flickers).
@export var settle: float = 0.9
## The least time between two street toasts, and between a district toast and a street one.
@export var street_gap: float = 7.0
## How far from a carriageway's edge still counts as on that street (m).
@export var street_reach: float = 6.0
## How often the place is looked up (s, real time).
@export var poll: float = 0.35

## AREA_TOAST=0 in the environment: no toast (the A/B).
static var enabled: bool = OS.get_environment("AREA_TOAST") != "0"
## Stills: a place and street shown at once and held (`show_now`).
static var forced: Array = []

enum Kind { NONE, DISTRICT, STREET }

var district := ""
var street := ""
## What is on screen and when it started (real seconds).
var kind: int = Kind.NONE
var shown_district := ""
var shown_street := ""
var age: float = 99.0
var _held := false

var _clock := 0.0
var _poll_t := 0.0
var _pending := ""
var _pending_since := 0.0
var _last_toast := -99.0
var _player: Node3D
var _city: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not forced.is_empty():
		show_now(str(forced[0]), str(forced[1]) if forced.size() > 1 else "", true)


## The street at a world XZ: the nearest of the four grid roads round its block whose
## carriageway is within `reach` m, or "" (open country, a block's middle).
static func street_at(plan: CityPlan, xz: Vector2, reach: float = 6.0) -> String:
	if plan == null or plan.zone_at(xz) != MacroMap.Zone.CITY:
		return ""
	var bi := plan.block_index_at(xz)
	var best := reach
	var name := ""
	for axis in [CityPlan.AXIS_X, CityPlan.AXIS_Z]:
		var v: float = xz.x if axis == CityPlan.AXIS_X else xz.y
		var i0: int = bi.x if axis == CityPlan.AXIS_X else bi.y
		for i in [i0, i0 + 1]:
			var d := absf(v - plan.road_pos(axis, i)) - plan.road_width(axis, i) * 0.5
			if d < best:
				best = d
				name = plan.road_name(axis, i)
	return name


## What a change from what is shown to (`d`, `s`) should put up, `since` seconds after the last
## toast: a district toast for a new place, a street toast for a new street in the same place
## once `gap` has passed, else nothing. Pure (the checks call it).
static func next_toast(shown_d: String, shown_s: String, d: String, s: String, since: float, gap: float) -> int:
	if d != "" and d != shown_d:
		return Kind.DISTRICT
	if s != "" and s != shown_s and since >= gap:
		return Kind.STREET
	return Kind.NONE


## Puts a toast up now (stills, and the checks). `keep` holds it on screen.
func show_now(d: String, s: String, keep: bool = false) -> void:
	shown_district = d
	shown_street = s
	kind = Kind.DISTRICT if d != "" else Kind.STREET
	age = fade_in if keep else 0.0
	_held = keep
	_last_toast = _clock
	queue_redraw()


## 0..1, how much of the toast is showing now.
func amount() -> float:
	if kind == Kind.NONE:
		return 0.0
	if _held:
		return 1.0
	var h := hold if kind == Kind.DISTRICT else street_hold
	return HudTheme.envelope(age, fade_in, h, fade_out)


func _process(delta: float) -> void:
	if not enabled or not is_visible_in_tree():
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_clock += dt
	age += dt
	if kind != Kind.NONE and not _held and amount() <= 0.0 and age > fade_in:
		kind = Kind.NONE
	_poll_t -= dt
	if _poll_t <= 0.0 and not _held:
		_poll_t = poll
		_look()
	if kind != Kind.NONE:
		queue_redraw()


func _look() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _city == null or not is_instance_valid(_city):
		_city = get_tree().get_first_node_in_group("city")
	if _player == null or _city == null or not _city.has_method("district_name_at"):
		return
	district = str(_city.call("district_name_at", _player.global_position))
	var plan: CityPlan = _city.get("plan")
	var wp: Vector3 = _city.call("world_position", _player.global_position)
	street = street_at(plan, Vector2(wp.x, wp.z), street_reach)
	# A new place must hold `settle` seconds first.
	if district != shown_district:
		if district != _pending:
			_pending = district
			_pending_since = _clock
		if _clock - _pending_since < settle:
			return
	var k := next_toast(shown_district, shown_street, district, street, _clock - _last_toast, street_gap)
	if k == Kind.DISTRICT:
		show_now(district, street)
	elif k == Kind.STREET:
		shown_street = street
		kind = Kind.STREET
		age = 0.0
		_last_toast = _clock


func _draw() -> void:
	var a := amount()
	if a <= 0.001:
		return
	var view := get_viewport_rect().size
	var s := HudTheme.scale(view)
	var safe := HudTheme.safe_rect(view)
	var big := kind == Kind.DISTRICT and shown_district != ""
	var title := shown_district.to_upper() if big else ""
	var sub := shown_street
	var f_title := HudTheme.display()
	var f_sub := HudTheme.text_medium()
	var px_title := int(round(52.0 * s))
	var px_sub := int(round((21.0 if big else 24.0) * s))
	var track := 3.0 * s
	# Slides in from the left as it comes; drifts up a little as it goes.
	var going := not _held and age > fade_in + (hold if big else street_hold)
	var dx := 0.0 if going else (1.0 - a) * -28.0 * s
	var dy := (1.0 - a) * -10.0 * s if going else 0.0
	var x := safe.position.x + dx
	var bottom := safe.end.y + dy
	var w_title := HudTheme.tracked_width(f_title, title, px_title, track)
	var w_sub := f_sub.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, px_sub).x
	var width := maxf(w_title, w_sub + 22.0 * s)
	var height := (px_title * 1.05 if big else 0.0) + px_sub * 1.6
	# A soft dark scrim under the words, so they read over a white sky or a sunlit wall: a
	# gradient from the lower left, never a box.
	var pad := 34.0 * s
	var r := Rect2(0.0, bottom - height - pad * 2.0, x + width + pad * 3.0, view.y - (bottom - height - pad * 2.0))
	var c0 := Color(0, 0, 0, 0.36 * a)
	var c1 := Color(0, 0, 0, 0.0)
	# A fan from the lower left corner: dark there, nothing on the three far edges.
	var mid := Vector2(r.position.x + r.size.x * 0.3, r.end.y - r.size.y * 0.25)
	draw_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y), r.position, Vector2(r.end.x, r.position.y), r.end]),
		PackedColorArray([c0, c1, c1, c1]))
	draw_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y), Vector2(r.position.x, mid.y), mid, Vector2(mid.x, r.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0.12 * a), c1, c1, c1]))
	var ink := Color(1, 1, 1, HudTheme.INK.a * a)
	var y := bottom
	if sub != "":
		# The amber rule, then the street.
		var rule_w := 14.0 * s
		var rule_y := y - px_sub * 0.36
		draw_rect(Rect2(x, rule_y - 1.5 * s, rule_w * a, 3.0 * s), Color(HudTheme.ACCENT.r, HudTheme.ACCENT.g, HudTheme.ACCENT.b, a))
		HudTheme.draw_tracked(self, f_sub, sub, Vector2(x + rule_w + 8.0 * s, y), px_sub, 0.4 * s, Color(1, 1, 1, HudTheme.SOFT.a * 1.2 * a))
		y -= px_sub * 1.45
	if big:
		HudTheme.draw_tracked(self, f_title, title, Vector2(x - 2.0 * s, y), px_title, track, ink)
