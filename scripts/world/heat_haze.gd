class_name HeatHaze
extends MeshInstance3D
## Heat shimmer over the far end of the street and the far field on hot afternoons
## (shaders/heat_haze.gdshader: one full-screen quad reading the screen, drawn first among the
## transparents). Weather drives `strength` (LaWeather.afternoon_heat() on a clear day, more in a
## Santa Ana). Forward+ desktop only, and only at HIGH and MEDIUM: on the web, on Compatibility
## and below MEDIUM it is never shown. Hidden whenever it has nothing to do, so a cool day or a
## night costs nothing.

## Peak displacement (1080-line pixels) at full heat.
@export var max_px: float = 2.4

var strength: float = 0.0:
	set(v):
		strength = v
		_refresh()
## Quality allows it (Weather sets this from the level: HIGH and MEDIUM).
var allowed: bool = true:
	set(v):
		allowed = v
		_refresh()
var _mat: ShaderMaterial


## Whether this machine can draw it at all.
static func supported() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless" \
		and RenderingServer.get_current_rendering_method() == "forward_plus"


func _ready() -> void:
	name = "HeatHaze"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/heat_haze.gdshader")
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	_mat.set_shader_parameter("max_px", max_px)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# A screen quad: never culled.
	extra_cull_margin = 16384.0
	_refresh()


func _refresh() -> void:
	if _mat == null:
		return
	var on := allowed and strength > 0.01 and supported()
	visible = on
	if on:
		_mat.set_shader_parameter("strength", strength)


func _process(_delta: float) -> void:
	if visible:
		var cam := get_viewport().get_camera_3d()
		if cam:
			global_position = cam.global_position
