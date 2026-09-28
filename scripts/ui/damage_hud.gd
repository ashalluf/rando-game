class_name DamageHud
extends ColorRect
## Being hurt, on screen (shaders/damage_hud.gdshader): the edges bloom dark red on every hit (by
## how hard), a red arc on a ring round the crosshair points at whoever fired and fades, and while
## health is low the edges pulse like a heartbeat. Listens to PlayerHealth.hit_taken; hides while
## the player is down (the OUT COLD card has the screen then). Built by DebugHud.

## How fast a hit's flash fades (per second), and how hard a hit counts toward it (per hp).
@export var hurt_decay: float = 2.4
@export var hurt_per_hp: float = 0.03
## How long a direction arc shows (s).
@export var arc_seconds: float = 1.5
## Health share under which the heartbeat starts, and its rate (beats a second).
@export var low_health: float = 0.35
@export var heart_rate: float = 1.3

var _mat: ShaderMaterial
var _player: Node
var _health: Node
var _hurt: float = 0.0
## [world position, age] of the last few hits' sources.
var _arcs: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(1, 1, 1, 1)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/damage_hud.gdshader")
	material = _mat
	visible = false


func _process(delta: float) -> void:
	if _health == null or not is_instance_valid(_health):
		_player = get_tree().get_first_node_in_group("player")
		_health = _player.get("health") if _player else null
		if _health and _health.has_signal("hit_taken"):
			_health.connect("hit_taken", _on_hit)
	# Real time: the wheel and the downed collapse slow the game clock.
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_hurt = move_toward(_hurt, 0.0, hurt_decay * dt)
	var frac := 1.0
	var down := false
	if _health:
		frac = float(_health.call("fraction"))
		down = bool(_health.get("downed"))
	var low := 0.0
	if frac < low_health and not down:
		var beat := pow(0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * heart_rate), 3.0)
		low = (1.0 - frac / low_health) * (0.45 + 0.55 * beat)
	var packed: Array[Vector4] = []
	var cam := get_viewport().get_camera_3d()
	for i in range(_arcs.size() - 1, -1, -1):
		_arcs[i][1] += dt
		if _arcs[i][1] > arc_seconds:
			_arcs.remove_at(i)
	for arc: Array in _arcs:
		var s := 1.0 - float(arc[1]) / arc_seconds
		var d := _screen_dir(cam, arc[0])
		packed.append(Vector4(d.x, d.y, s * s, 0.0))
	while packed.size() < 4:
		packed.append(Vector4.ZERO)
	var any := not down and (_hurt > 0.001 or low > 0.001 or not _arcs.is_empty())
	visible = any
	if not any:
		return
	# Built in code under a CanvasLayer, its anchors never give it the screen: size it by hand.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_mat.set_shader_parameter("rect_px", size)
	_mat.set_shader_parameter("hurt", _hurt)
	_mat.set_shader_parameter("low", low)
	_mat.set_shader_parameter("arcs", packed)


func _on_hit(amount: float, from: Vector3) -> void:
	_hurt = clampf(_hurt + amount * hurt_per_hp, 0.0, 1.0)
	if from != Vector3.INF:
		_arcs.append([from, 0.0])
		while _arcs.size() > 4:
			_arcs.pop_front()


## Where `at` lies round the crosshair, as a unit vector on screen (up = straight ahead).
func _screen_dir(cam: Camera3D, at: Vector3) -> Vector2:
	if cam == null:
		return Vector2.UP
	var to := at - cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var right := cam.global_basis.x
	right.y = 0.0
	if fwd.length_squared() < 1e-6:
		return Vector2.UP
	var v := Vector2(to.dot(right.normalized()), -to.dot(fwd.normalized()))
	return v.normalized() if v.length_squared() > 1e-6 else Vector2.UP
