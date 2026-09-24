extends Control
## Simple ring-and-dot crosshair. Turns cyan while the gravity gun holds something, and red with
## brackets round the target while GTA-style aim holds a lock (Player.lock_on).

@export var color: Color = Color(1, 1, 1, 0.9)
@export var hold_color: Color = Color(0.3, 0.9, 1.0, 1.0)
@export var lock_color: Color = Color(1.0, 0.22, 0.18, 1.0)
@export var radius: float = 7.0
## Bracket size round a locked target: this many pixels at 1 m, clamped to the range below.
@export var bracket_scale: float = 700.0
@export var bracket_min: float = 12.0
@export var bracket_max: float = 56.0

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
	var lock: LockOn = _player.lock_on if _player else null
	if lock and lock.aiming:
		# Red once something is locked.
		c = lock_color if lock.target else c
		if lock.target and is_instance_valid(lock.target):
			_draw_brackets(lock.aim_point())
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, c, 1.5, true)
	draw_circle(Vector2.ZERO, 1.5, c)


## Four corner brackets round the locked target, sized by its distance.
func _draw_brackets(point: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(point):
		return
	var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * cam.unproject_position(point)
	var half := clampf(bracket_scale / maxf(cam.global_position.distance_to(point), 1.0), bracket_min, bracket_max)
	var arm := half * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := at + Vector2(sx, sy) * half
			draw_line(corner, corner - Vector2(sx * arm, 0.0), lock_color, 2.0, true)
			draw_line(corner, corner - Vector2(0.0, sy * arm), lock_color, 2.0, true)
