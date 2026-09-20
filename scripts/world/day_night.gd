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
@export_group("Sky")
@export var day_sky_top: Color = Color(0.08, 0.28, 0.76)
@export var day_horizon: Color = Color(0.62, 0.78, 0.95)
@export var dusk_sky_top: Color = Color(0.16, 0.18, 0.42)
@export var dusk_horizon: Color = Color(1.0, 0.55, 0.3)
@export var night_sky_top: Color = Color(0.02, 0.035, 0.09)
@export var night_horizon: Color = Color(0.07, 0.09, 0.19)
## Cloud tints by day, at dusk and by night (lit side / shadow side).
@export var day_cloud: Color = Color(1.0, 1.0, 1.0)
@export var day_cloud_shadow: Color = Color(0.58, 0.63, 0.74)
@export var dusk_cloud: Color = Color(1.0, 0.72, 0.5)
@export var dusk_cloud_shadow: Color = Color(0.45, 0.3, 0.42)
## Cloud amount 0..1. Changes slowly over the day for variety.
@export var cloud_coverage: float = 0.42
## Horizon haze in the sky shader by day and at dusk (0 clear, 1 milky).
@export var day_haze: float = 0.22
@export var dusk_haze: float = 0.5
@export_group("")
## Ambient light color and strength by day and by night (moonlight).
@export var day_ambient: Color = Color(0.62, 0.7, 0.85)
@export var night_ambient: Color = Color(0.3, 0.38, 0.6)
@export var day_ambient_energy: float = 0.55
@export var night_ambient_energy: float = 0.55
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export_node_path("WorldEnvironment") var environment_path: NodePath

## Weather hooks (set by the Weather node every frame): extra cloud cover and how dark it is.
var cloud_extra: float = 0.0
var weather_darken: float = 0.0

## Hour of the day, 0..24.
var hour: float = 9.0
var night_factor: float = 0.0

var _sun: DirectionalLight3D
var _env: Environment
## How bright the street lamps burn at full night. Quality scales this down at the low levels.
@export var lamp_energy: float = 2.6
var lamp_scale: float = 1.0
var _lamp_level: float = -1.0
var _lamp_timer: float = 0.0
var _sky: ShaderMaterial
var _paused: bool = false


func _ready() -> void:
	hour = start_hour
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
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
	# Golden hour: about 1.5 h either side of sunrise and sunset.
	var dusk := clampf(1.0 - absf(elevation) * 2.6, 0.0, 1.0) * float(elevation > -0.3)
	if _sun:
		# By day the sun tracks the hour; by night the same light is a high, bright moon.
		var pitch := -elevation * 85.0 if elevation > 0.0 else -55.0
		var azimuth := 180.0 * t + sun_rotation_z_degrees if elevation > 0.0 else 120.0
		_sun.rotation_degrees = Vector3(pitch, azimuth, 0.0)
		_sun.light_color = day_sun_color.lerp(dusk_sun_color, dusk).lerp(night_sun_color, night_factor)
		var flash: float = _sun.get_meta("weather_flash", 0.0)
		_sun.light_energy = lerpf(night_sun_energy, day_sun_energy, daylight) * (1.0 - 0.75 * weather_darken) + flash * 2.5
		if flash > 0.0:
			_sun.light_color = _sun.light_color.lerp(Color(0.85, 0.9, 1.0), clampf(flash, 0.0, 1.0))
		_sun.shadow_enabled = true
	if _sky:
		var horizon := day_horizon.lerp(dusk_horizon, dusk).lerp(night_horizon, night_factor)
		var storm_top := Color(0.16, 0.17, 0.2)
		var storm_horizon := Color(0.3, 0.31, 0.34)
		_sky.set_shader_parameter("sky_top", day_sky_top.lerp(dusk_sky_top, dusk).lerp(night_sky_top, night_factor).lerp(storm_top, weather_darken * (1.0 - night_factor * 0.6)))
		_sky.set_shader_parameter("sky_horizon", horizon.lerp(storm_horizon, weather_darken * (1.0 - night_factor * 0.6)))
		_sky.set_shader_parameter("cloud_color", day_cloud.lerp(dusk_cloud, dusk))
		_sky.set_shader_parameter("cloud_coverage", clampf(cloud_coverage + 0.12 * sin(hour * 0.9) + cloud_extra, 0.0, 0.98))
		_sky.set_shader_parameter("cloud_shadow", day_cloud_shadow.lerp(dusk_cloud_shadow, dusk).lerp(Color(0.2, 0.2, 0.24), weather_darken))
		_sky.set_shader_parameter("stars", night_factor)
		_sky.set_shader_parameter("haze", lerpf(day_haze, dusk_haze, dusk))
		_sky.set_shader_parameter("sun_glow", lerpf(0.9, 1.6, dusk))
		# Under the horizon is the far haze the ground plane fades into, not a grey floor.
		_sky.set_shader_parameter("ground_color", horizon.lerp(Color(0.32, 0.34, 0.37), 0.30))
		# The ground follower's horizon has to wash out into the same colour the sky meets it
		# with, or the land ends in a hard line however good the haze is.
		var streamer := get_parent()
		if streamer and streamer.has_method("set_ground_haze"):
			var hz: Color = horizon.lerp(storm_horizon, weather_darken * (1.0 - night_factor * 0.6))
			# A directional light shines along -Z, so +Z points back at the sun.
			streamer.set_ground_haze(hz, _sun.global_transform.basis.z if _sun else Vector3.UP)
	if _env:
		_env.fog_light_color = day_horizon.lerp(night_horizon, night_factor)
		# Ambient comes from the sky cubemap, so shadows take the sky's own colour (blue at
		# midday, warm at dusk) instead of a flat grey fill: the single biggest realism win in
		# outdoor lighting. At night the sky is nearly black, so we blend back toward a colour
		# fill so the city does not go pitch dark.
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = lerpf(1.0, 0.35, night_factor)
		_env.ambient_light_color = day_ambient.lerp(night_ambient, night_factor)
		_env.ambient_light_energy = lerpf(day_ambient_energy, night_ambient_energy, night_factor) * (1.0 - 0.35 * weather_darken)
		_env.fog_light_color = _env.fog_light_color.lerp(Color(0.35, 0.37, 0.4), weather_darken)
	# Street lamps. Setting hundreds of lights every frame is wasteful, but only refreshing when
	# the value moves leaves every lamp that streamed in since the last change sitting at zero,
	# which is why the streets stayed black the first time. Refresh on a slow tick instead, so
	# newly loaded chunks pick the level up within a third of a second.
	var want := night_factor * lamp_energy * lamp_scale
	# _apply() is also called from _ready(), where there is no delta parameter to use.
	_lamp_timer -= get_process_delta_time()
	if _lamp_timer <= 0.0 or absf(want - _lamp_level) > 0.04:
		_lamp_timer = 0.35
		_lamp_level = want
		for light in get_tree().get_nodes_in_group("lamp_light"):
			(light as OmniLight3D).light_energy = want
	RenderingServer.global_shader_parameter_set("night_factor", night_factor)
