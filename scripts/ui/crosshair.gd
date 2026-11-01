class_name Crosshair
extends Control
## Simple ring-and-dot crosshair. Turns red with brackets round the target while GTA-style aim
## holds a lock (Player.lock_on). A hit marker flashes on it when a round lands: four short
## diagonal strokes, white on a car or a thing, red on a person (`mark_hit()`, called by the guns).

@export var color: Color = Color(1, 1, 1, 0.9)
@export var lock_color: Color = Color(1.0, 0.22, 0.18, 1.0)
@export var radius: float = 7.0
## Bracket size round a locked target: this many pixels at 1 m, clamped to the range below.
@export var bracket_scale: float = 700.0
@export var bracket_min: float = 12.0
@export var bracket_max: float = 56.0
## How long a hit marker shows (real seconds), and its strokes' gap from the centre and length.
@export var hit_seconds: float = 0.22
@export var hit_gap: float = 7.0
@export var hit_length: float = 8.0
@export var hit_color: Color = Color(1, 1, 1, 0.95)
@export var kill_color: Color = Color(1.0, 0.2, 0.16, 1.0)

static var _hit_ms: int = -100000
static var _hit_person: bool = false

var _player: Player


## A round landed: `person` for someone hit (red), else a car or a thing (white). A person hit
## in the same instant keeps the marker red.
static func mark_hit(person: bool) -> void:
	var now := Time.get_ticks_msec()
	_hit_person = person or (_hit_person and now - _hit_ms < 30)
	_hit_ms = now


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	queue_redraw()


func _draw() -> void:
	var c := color
	var lock: LockOn = _player.lock_on if _player else null
	if lock and lock.aiming:
		# Red once something is locked.
		c = lock_color if lock.target else c
		if lock.target and is_instance_valid(lock.target):
			_draw_brackets(lock.aim_point())
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, c, 1.5, true)
	draw_circle(Vector2.ZERO, 1.5, c)
	_draw_hit_marker()


## Four short diagonal strokes round the centre, popping out a little and fading.
func _draw_hit_marker() -> void:
	var age := float(Time.get_ticks_msec() - _hit_ms) / 1000.0
	if age < 0.0 or age > hit_seconds:
		return
	var t := age / hit_seconds
	var col := kill_color if _hit_person else hit_color
	col.a *= 1.0 - t * t
	var gap := hit_gap + 3.0 * (1.0 - (1.0 - t) * (1.0 - t))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var d := Vector2(sx, sy).normalized()
			draw_line(d * gap + Vector2(0.0, 1.0), d * (gap + hit_length) + Vector2(0.0, 1.0), Color(0, 0, 0, col.a * 0.4), 3.0, true)
			draw_line(d * gap, d * (gap + hit_length), col, 2.0, true)


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
