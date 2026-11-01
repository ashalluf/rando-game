class_name CloudShadows
extends MeshInstance3D
## Moving cloud shadows on the city, the hills and the sea, cast by the clouds the sky really draws
## (fleet wave 5, `sky-clouds-3`; docs/HANDOFF.md "Cloud shadows from the real clouds").
##
## Before this the streamed city had none, and the horizon plane and the far sea had their own,
## from a noise field that had nothing to do with the cumulus overhead: a shadow crawled over the
## mountains under a clear patch of sky and the ground under a heap stayed in full sun.
##
## One full-screen quad (shaders/cloud_shadow_screen.gdshader) multiplies the lit picture by the
## sun a cloud takes away at each pixel's ground point, worked out from the sky volume's own
## weather map (shaders/cloud_shadow.gdshaderinc, cumulus()'s columns). Every number it needs is
## copied off the sky material each frame, so the shadows lie under the clouds you see, offset
## by the sun and drifting with them. Forward+ desktop only and only while the sky draws its
## volume (HIGH and MEDIUM): elsewhere the old painted noise on the far plane and the sea stays.
## While it runs the plane's and the sea's own noise shadows are turned off (no double shadow).
## DayNight makes it (one line); CLOUD_SHADOWS=0 in the environment is the A/B.

## How much of a sunlit pixel's light a full cloud shadow takes away at noon, in clear air.
@export var strength: float = 0.5
## The sun's elevation (sine) over which the shadows come in after dawn and go before dusk.
@export var sun_low: float = 0.05
@export var sun_high: float = 0.2
## Coverage over which a broken sky closes into overcast and the shadows merge into the shade.
@export var overcast_from: float = 0.74
@export var overcast_to: float = 0.92

var _mat: ShaderMaterial
var _day: Node
var _sky: ShaderMaterial
var _plane_off: bool = false
## What was pushed last (the checks read it): strength and whether it is drawn.
var last_strength: float = 0.0


static func enabled() -> bool:
	return OS.get_environment("CLOUD_SHADOWS") != "0"


## Whether this machine can draw it at all (the volume and the normal buffer are Forward+ only).
static func supported() -> bool:
	return enabled() and not OS.has_feature("web") and DisplayServer.get_name() != "headless" \
		and RenderingServer.get_current_rendering_method() == "forward_plus"


## How strong the shadows are for a sun at `sun_y` (sine of its elevation), a sky at `coverage`,
## `darken` the weather's darkening (0..1) and `marine` the marine layer under the camera. Pure.
static func strength_for(base: float, sun_y: float, coverage: float, darken: float, marine: float,
		lo: float = 0.05, hi: float = 0.2, ov0: float = 0.74, ov1: float = 0.92) -> float:
	var s := base * smoothstep(lo, hi, sun_y)
	s *= 1.0 - smoothstep(ov0, ov1, coverage)
	s *= clampf(1.0 - 1.4 * darken, 0.0, 1.0)
	s *= clampf(1.0 - marine, 0.0, 1.0)
	return s


func setup(day: Node, sky: ShaderMaterial) -> void:
	_day = day
	_sky = sky


func _ready() -> void:
	name = "CloudShadows"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mesh = quad
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/cloud_shadow_screen.gdshader")
	# Before every transparent: glass, water's foam, smoke and particles land on top unshadowed.
	_mat.render_priority = Material.RENDER_PRIORITY_MIN
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 16384.0
	visible = false


func _process(_delta: float) -> void:
	if _sky == null or _mat == null:
		return
	var volume := float(_sky.get_shader_parameter("cloud_volume")) > 0.5 \
		and float(_sky.get_shader_parameter("cloud_detail")) > 0.5
	var sun := _sun_dir()
	var cov := float(_sky.get_shader_parameter("cloud_coverage"))
	var darken := float(_day.get("weather_darken")) if _day else 0.0
	var marine := float(_day.get("marine")) if _day else 0.0
	var s := strength_for(strength, sun.y, cov, darken, marine, sun_low, sun_high, overcast_from, overcast_to)
	if not volume:
		s = 0.0
	last_strength = s
	_set_plane_shadows(volume)
	visible = s > 0.002
	if not visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
	_mat.set_shader_parameter("strength", s)
	if OS.get_environment("CLOUD_SHADOW_DEBUG") == "1":
		_mat.set_shader_parameter("debug_field", 1.0)
	_mat.set_shader_parameter("cs_coverage", cov)
	for k in [["cs_wind", "cloud_wind"], ["cs_weather_tile", "weather_tile"], ["cs_billow_tile", "billow_tile"],
			["cs_base", "cloud_base"], ["cs_depth", "cloud_depth"],
			["cs_weather", "cloud_weather"], ["cs_shape", "cloud_shape"]]:
		var v: Variant = _sky.get_shader_parameter(k[1])
		if v != null:
			_mat.set_shader_parameter(k[0], v)
	var frag := 0.0
	var sd: Variant = _sky.get_shader_parameter("sky_day")
	var df: Variant = _sky.get_shader_parameter("day_fragments")
	if sd != null:
		frag = float(sd) * (float(df) if df != null else 0.18)
	_mat.set_shader_parameter("cs_fragments", frag)


func _sun_dir() -> Vector3:
	var sun: Variant = _day.get("_sun") if _day else null
	if sun is DirectionalLight3D:
		return (sun as DirectionalLight3D).global_transform.basis.z.normalized()
	var v: Variant = _sky.get_shader_parameter("sun_dir")
	return (v as Vector3).normalized() if v is Vector3 else Vector3.UP


## The far plane's and the sea's own noise shadows: off while the real ones are drawn (only in
## the city: a tool scene with no streamer has neither).
func _set_plane_shadows(real: bool) -> void:
	if real == _plane_off:
		return
	var keep := 0.0 if real else 0.55
	var streamer := _day.get_parent() if _day else null
	var gm: Variant = streamer.get("_ground_material") if streamer else null
	if not gm is ShaderMaterial:
		return
	_plane_off = real
	(gm as ShaderMaterial).set_shader_parameter("cloud_shadow_strength", keep)
	# By path: naming PropFactory here would compile half the city into every --script tool
	# that loads DayNight (sky_shot.gd), before the autoloads exist.
	var pf := load("res://scripts/world/prop_factory.gd") as GDScript
	var ocean: Variant = pf.call("ocean_material") if pf else null
	if ocean is ShaderMaterial:
		(ocean as ShaderMaterial).set_shader_parameter("cloud_shadow_strength", keep)
