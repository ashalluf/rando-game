class_name DayNight
extends Node
## Day/night cycle: moves the sun, tints the sky and fog, and drives the `night_factor` global
## shader parameter that makes windows and lamps glow after dark.

## Real seconds for a full day.
@export var day_length_seconds: float = 480.0
@export var start_hour: float = 9.0
@export var sun_rotation_z_degrees: float = 35.0
@export var day_sun_color: Color = Color(1.0, 0.97, 0.9)
@export var dusk_sun_color: Color = Color(1.0, 0.6, 0.35)
@export var night_sun_color: Color = Color(0.62, 0.72, 1.0)
@export var day_sun_energy: float = 1.0
@export var night_sun_energy: float = 0.55
@export var day_sky_top: Color = Color(0.33, 0.55, 0.92)
@export var day_horizon: Color = Color(0.78, 0.86, 0.96)
@export var dusk_horizon: Color = Color(0.95, 0.6, 0.4)
@export var night_sky_top: Color = Color(0.05, 0.08, 0.18)
@export var night_horizon: Color = Color(0.16, 0.2, 0.34)
## Ambient light color and strength by day and by night (moonlight).
@export var day_ambient: Color = Color(0.62, 0.7, 0.85)
@export var night_ambient: Color = Color(0.3, 0.38, 0.6)
@export var day_ambient_energy: float = 0.55
@export var night_ambient_energy: float = 0.55
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export_node_path("WorldEnvironment") var environment_path: NodePath

## Hour of the day, 0..24.
var hour: float = 9.0
var night_factor: float = 0.0

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var _paused: bool = false


func _ready() -> void:
	hour = start_hour
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky:
			_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_apply_override()
	_apply()


func _process(delta: float) -> void:
	if not _paused:
		hour = fmod(hour + delta * 24.0 / day_length_seconds, 24.0)
	_apply()


func set_paused(on: bool) -> void:
	_paused = on


func clock_text() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


## Debug: ?hour=21 on the web, -- --hour=21 on desktop.
func _apply_override() -> void:
	var text := ""
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&"):
				if part.begins_with("hour="):
					text = part.trim_prefix("hour=")
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--hour="):
				text = arg.trim_prefix("--hour=")
	if not text.is_empty():
		hour = fmod(text.to_float(), 24.0)


func _apply() -> void:
	# Sun elevation: up at 6, peak at 12, down at 18.
	var t := (hour - 6.0) / 12.0 # 0..1 across the day
	var elevation := sin(t * PI) # negative at night
	var daylight := clampf(elevation * 3.0, 0.0, 1.0)
	night_factor = 1.0 - clampf((elevation + 0.05) * 6.0, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elevation) * 5.0, 0.0, 1.0) * float(elevation > -0.15)
	if _sun:
		# By day the sun tracks the hour; by night the same light is a high, bright moon.
		var pitch := -elevation * 85.0 if elevation > 0.0 else -55.0
		var azimuth := 180.0 * t + sun_rotation_z_degrees if elevation > 0.0 else 120.0
		_sun.rotation_degrees = Vector3(pitch, azimuth, 0.0)
		_sun.light_color = day_sun_color.lerp(dusk_sun_color, dusk).lerp(night_sun_color, night_factor)
		_sun.light_energy = lerpf(night_sun_energy, day_sun_energy, daylight)
		_sun.shadow_enabled = true
	if _sky:
		_sky.sky_top_color = day_sky_top.lerp(night_sky_top, night_factor)
		var horizon := day_horizon.lerp(dusk_horizon, dusk).lerp(night_horizon, night_factor)
		_sky.sky_horizon_color = horizon
		_sky.ground_horizon_color = horizon
	if _env:
		_env.fog_light_color = day_horizon.lerp(night_horizon, night_factor)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = day_ambient.lerp(night_ambient, night_factor)
		_env.ambient_light_energy = lerpf(day_ambient_energy, night_ambient_energy, night_factor)
	RenderingServer.global_shader_parameter_set("night_factor", night_factor)
