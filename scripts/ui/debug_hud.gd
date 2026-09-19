extends CanvasLayer
## Debug overlay: FPS, speed, jump peak, physics body counts, control hints. F1 toggles.

@onready var stats: Label = $Stats
@onready var hints: Label = $Hints

var _player: Player


func _ready() -> void:
	hints.text = "WASD move   Shift sprint   Space jump (again in air)   Mouse look   R respawn   Esc release mouse   F1 hide\n" \
		+ "Gamepad: left stick move   L3 sprint   A jump   right stick look   Back respawn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var budget := get_node_or_null("/root/PhysicsBudget")
	var bodies: int = budget.active_body_count() if budget else 0
	var frozen: int = budget.frozen_count if budget else 0
	stats.text = "FPS %d   speed %.1f m/s   vertical %+.1f m/s   %s   air jumps %d\n" % [
		Engine.get_frames_per_second(), _player.horizontal_speed(), _player.velocity.y,
		"on floor" if _player.is_on_floor() else "airborne", _player.air_jumps_left,
	] + "last jump peak %.1f m   physics props %d (frozen %d)" % [_player.last_jump_peak, bodies, frozen]
