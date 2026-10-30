extends Control
## Ring drawn on top of the round minimap (the frame itself is clipped, so the ring lives here).

@export var color: Color = Color(0.1, 0.1, 0.12, 0.95)
@export var width: float = 4.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_arc(size * 0.5, size.x * 0.5 - width * 0.5, 0.0, TAU, 96, color, width, true)
