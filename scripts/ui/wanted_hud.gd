class_name WantedHud
extends Control
## The wanted stars (top right, under the weapon list) and the health bar (over the minimap),
## both in the weapon wheel's frosted glass (shaders/glass_hud.gdshader). Five stars always,
## lit ones filled with white light and empty ones outlined glass, so the row shows how far it
## can go; they flash while the police have lost sight of the player (Police.flashing). The row
## fades in with the first star and out after the last. The health bar is always there, fills
## from the left, goes red when low and pulses red when hit.
##
## Reads the Police node (group "wanted") and the player's PlayerHealth every frame; both are
## plain properties, so this costs a handful of uniform writes.

## Star size as a fraction of the viewport height (clamped), and the margin from the top right.
@export var star_size: float = 0.036
@export var star_margin: Vector2 = Vector2(16.0, 44.0)
## How fast a star lights or goes out (per second), and the flash rate while the police have
## lost the player (flashes per second).
@export var star_ease: float = 5.0
@export var flash_rate: float = 2.2
## The health bar: size in pixels, sitting this far above the minimap.
@export var bar_size: Vector2 = Vector2(260.0, 22.0)
@export var bar_gap: float = 6.0

var _stars: ColorRect
var _bar: ColorRect
var _stars_mat: ShaderMaterial
var _bar_mat: ShaderMaterial
var _fill := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _show: float = 0.0
var _hurt: float = 0.0
var _last_hit: int = -100000
var _police: Node
var _player: Node


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader: Shader = load("res://shaders/glass_hud.gdshader")
	_stars = ColorRect.new()
	_stars.name = "Stars"
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stars_mat = ShaderMaterial.new()
	_stars_mat.shader = shader
	_stars_mat.set_shader_parameter("mode", 0)
	_stars.material = _stars_mat
	add_child(_stars)
	_bar = ColorRect.new()
	_bar.name = "Health"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = shader
	_bar_mat.set_shader_parameter("mode", 1)
	_bar.material = _bar_mat
	add_child(_bar)
	_stars.modulate.a = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _police == null or not is_instance_valid(_police):
		_police = get_tree().get_first_node_in_group("wanted")
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	# Real time: the weapon wheel and the downed screen slow the game clock down.
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_layout()
	var stars := int(_police.get("stars")) if _police else 0
	var flashing := bool(_police.get("flashing")) if _police else false
	for k in 5:
		_fill[k] = move_toward(_fill[k], 1.0 if k < stars else 0.0, star_ease * dt)
	_stars_mat.set_shader_parameter("star_fill", _fill)
	var flash := 0.0
	if flashing:
		flash = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * flash_rate)
	_stars_mat.set_shader_parameter("flash", flash)
	var any := stars > 0 or _fill[0] > 0.01
	_show = move_toward(_show, 1.0 if any else 0.0, dt * 3.0)
	_stars.modulate.a = _show
	_stars.visible = _show > 0.001
	var health: Node = _player.get("health") if _player else null
	var frac := 1.0
	if health:
		frac = float(health.call("fraction"))
		var hit: int = int(health.get("last_hit_ms"))
		if hit != _last_hit:
			_last_hit = hit
			_hurt = 1.0
	_hurt = move_toward(_hurt, 0.0, dt * 2.5)
	_bar_mat.set_shader_parameter("bar_fill", frac)
	_bar_mat.set_shader_parameter("bar_hurt", _hurt)


## Stars under the weapon list, the bar over the minimap (which is 260 px, 24 px from the
## bottom-right corner in debug_hud.tscn).
func _layout() -> void:
	var view := get_viewport_rect().size
	var r := clampf(view.y * star_size * 0.5, 11.0, 30.0)
	var gap := r * 0.42
	var w := 5.0 * 2.0 * r + 4.0 * gap + 20.0
	var h := 2.0 * r + 20.0
	_stars.size = Vector2(w, h)
	_stars.position = Vector2(view.x - star_margin.x - w + 10.0, star_margin.y)
	_stars_mat.set_shader_parameter("rect_px", _stars.size)
	_stars_mat.set_shader_parameter("star_r", r)
	_stars_mat.set_shader_parameter("star_gap", gap)
	_stars_mat.set_shader_parameter("star_glow_px", r * 0.4)
	_bar.size = bar_size
	_bar.position = Vector2(view.x - 24.0 - bar_size.x, view.y - 24.0 - 260.0 - bar_gap - bar_size.y)
	_bar_mat.set_shader_parameter("rect_px", _bar.size)
