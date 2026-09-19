extends Control
## Simple ring-and-dot crosshair. Turns cyan while the gravity gun holds something.

@export var color: Color = Color(1, 1, 1, 0.9)
@export var hold_color: Color = Color(0.3, 0.9, 1.0, 1.0)
@export var radius: float = 7.0

var _player: Player


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	queue_redraw()


func _draw() -> void:
	var c := color
	if _player and _player.weapon_manager and _player.weapon_manager.current is GravityGun:
		if (_player.weapon_manager.current as GravityGun).is_holding():
			c = hold_color
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, c, 1.5, true)
	draw_circle(Vector2.ZERO, 1.5, c)
