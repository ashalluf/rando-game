extends Control
## Round mask and border for the minimap: draws a disc, and clips the child map to it.
##
## It is laid out at 1080 lines (the size and margin in debug_hud.tscn) and SCALED with the
## window (`hud_scale()`, the weapon panel's rule), about its bottom-right corner, with the ring
## (MinimapBorder, a sibling) beside it. Drawn at a fixed 260 px it was a quarter of the size it
## should be at 4K - and a Retina Mac's maximised window is 2,234 lines. The map inside keeps its
## 260 px canvas, so every line width, glyph and font in it scales with it.

@export var border_color: Color = Color(0.1, 0.1, 0.12, 0.95)
@export var border_width: float = 4.0

## The frame's size and its margin from the corner at 1080 lines (read from the scene).
var base_size: float = 260.0
var base_margin: float = 24.0


## The HUD's scale for a viewport this size: 1 at 1080 lines (WeaponHud's rule).
static func hud_scale(view: Vector2) -> float:
	return clampf(view.y / 1080.0, 0.7, 2.0)


func _ready() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_size = offset_right - offset_left
	base_margin = -offset_right
	get_viewport().size_changed.connect(layout)
	layout()


## Places the frame and the ring for the viewport's size.
func layout() -> void:
	var s := hud_scale(get_viewport_rect().size)
	for c: Control in [self, get_parent().get_node_or_null("MinimapBorder") as Control]:
		if c == null:
			continue
		c.offset_right = -base_margin * s
		c.offset_bottom = -base_margin * s
		c.offset_left = c.offset_right - base_size
		c.offset_top = c.offset_bottom - base_size
		c.pivot_offset = Vector2(base_size, base_size)
		c.scale = Vector2(s, s)


## The frame's rectangle on screen (scaled).
func screen_rect() -> Rect2:
	var s := scale.x
	var end := get_viewport_rect().size - Vector2.ONE * base_margin * s
	return Rect2(end - Vector2.ONE * base_size * s, Vector2.ONE * base_size * s)


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, size.x * 0.5, Color.WHITE)
