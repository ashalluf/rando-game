extends Control
## Round mask and border for the minimap: draws a disc, and clips the child map to it.

@export var border_color: Color = Color(0.1, 0.1, 0.12, 0.95)
@export var border_width: float = 4.0


func _ready() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, size.x * 0.5, Color.WHITE)
