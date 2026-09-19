extends CanvasLayer
## Debug overlay: FPS, speed, jump peak, physics body counts, weapon, control hints. F1 toggles.

@onready var stats: Label = $Stats
@onready var hints: Label = $Hints
@onready var weapon_label: Label = $Weapon

var _player: Player


func _ready() -> void:
	if OS.has_feature("web"):
		hints.text = "Click the game to grab the mouse.\n"
	hints.text += "WASD move   Shift boost (hold; in the air it follows where you look)   Space jump (again in air)   Mouse look   E get in / out of a car\n" \
		+ "Left click fire   Right click drop (gravity gun)   1 / 2 / 3 or scroll to switch weapons   R respawn   Esc release mouse   F1 hide\n" \
		+ "Driving: W / S gas and brake   A / D steer   Shift nitro   Space handbrake   in the air W / S flip, A / D roll\n" \
		+ "Gamepad: left stick move   B boost   A jump   Y car   right stick look   RT fire   LT drop   LB / RB switch   Back respawn"


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
	var state := "on floor" if _player.is_on_floor() else "airborne"
	if _player.is_driving():
		state = "driving %s" % _player.vehicle.display_name()
	if _player.is_boosting():
		state += "  BOOST"
	stats.text = "FPS %d   speed %.1f m/s   vertical %+.1f m/s   %s   air jumps %d\n" % [
		Engine.get_frames_per_second(), _player.horizontal_speed(), _player.velocity.y,
		state, _player.air_jumps_left,
	] + "last jump peak %.1f m   physics props %d (frozen %d)" % [_player.last_jump_peak, bodies, frozen]
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("district_name_at"):
		stats.text += "   district: %s" % city.district_name_at(_player.global_position)
	var peds := get_tree().get_nodes_in_group("pedestrian").size()
	var traffic := get_tree().get_first_node_in_group("traffic")
	stats.text += "   people %d" % peds
	if city and city.has_method("chunk_counts"):
		var counts: Vector2i = city.chunk_counts()
		var wp: Vector3 = city.world_position(_player.global_position)
		stats.text += "   chunks %d full / %d far   world pos %d, %d   wrecked %d" % [counts.x, counts.y, int(wp.x), int(wp.z), WorldState.destroyed_count()]

	var manager := _player.weapon_manager
	if manager and manager.current:
		var parts: PackedStringArray = []
		for i in manager.weapons.size():
			var name := manager.weapons[i].display_name
			parts.append("[%d] %s" % [i + 1, name.to_upper() if manager.weapons[i] == manager.current else name])
		weapon_label.text = "   ".join(parts)
