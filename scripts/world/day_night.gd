class_name DayNight
extends Node
## Day/night cycle: moves the sun and the moon, tints the sky and fog, and drives the
## `night_factor` global shader parameter that makes windows and lamps glow after dark.

## Real seconds for a full day. 2880 is 48 minutes, two real seconds per game minute - the pace
## the big open-world games settled on. At 480 (owner, 2026-09-23: "the day/night cycle is too
## fast") a sunset was over in under a minute and a whole day in eight.
@export var day_length_seconds: float = 2880.0
@export var start_hour: float = 9.0
@export var sun_rotation_z_degrees: float = 35.0
@export var day_sun_color: Color = Color(1.0, 0.94, 0.82)
@export var dusk_sun_color: Color = Color(1.0, 0.6, 0.35)
@export var night_sun_color: Color = Color(0.62, 0.72, 1.0)
## Key light strength by day. The sun has to out-run the ambient fill by a good margin or
## every shadow turns grey and the frame has no value contrast left - the single thing that
## made the old aerials read as a pastel model village rather than a city at noon.
@export var day_sun_energy: float = 1.3
## The moon. 0.55 lit every roof in the city brighter than the night sky above it (roofs 100-120
## of 255 against a sky of 50 in a Forward+ aerial at 21:00): day-for-night, not a night.
@export var night_sun_energy: float = 0.3
## Sun elevations the golden-hour tint fades out between once the sun is under the horizon
## (x fully faded, y still full strength; elevation is the sine of the arc angle, not degrees).
@export var dusk_fade_elevation: Vector2 = Vector2(-0.36, -0.24)
@export_group("Sky")
@export var day_sky_top: Color = Color(0.08, 0.28, 0.76)
@export var day_horizon: Color = Color(0.62, 0.78, 0.95)
@export var dusk_sky_top: Color = Color(0.16, 0.18, 0.42)
@export var dusk_horizon: Color = Color(1.0, 0.55, 0.3)
@export var night_sky_top: Color = Color(0.02, 0.035, 0.09)
@export var night_horizon: Color = Color(0.07, 0.09, 0.19)
## An overcast night over the city (rain, storm): cloud base overhead, the horizon, and the rain
## haze, all lit from below by the streets rather than by the sky.
@export var night_storm_top: Color = Color(0.045, 0.042, 0.045)
@export var night_storm_horizon: Color = Color(0.14, 0.105, 0.08)
@export var night_storm_fog: Color = Color(0.11, 0.09, 0.075)
## The light an overcast night's cloud base carries (linear, the sky shader's `night_glow`).
@export var night_storm_glow: Vector3 = Vector3(0.042, 0.030, 0.021)
## Cloud tints by day, at dusk and by night (lit side / shadow side).
@export var day_cloud: Color = Color(1.0, 1.0, 1.0)
@export var day_cloud_shadow: Color = Color(0.58, 0.63, 0.74)
@export var dusk_cloud: Color = Color(1.0, 0.72, 0.5)
@export var dusk_cloud_shadow: Color = Color(0.45, 0.3, 0.42)
## Cloud amount 0..1. Changes slowly over the day for variety.
@export var cloud_coverage: float = 0.42
## How much of the mid-altitude cloud deck there is (0 off). It drifts slower than the cumulus,
## which is most of what makes a sky read as weather rather than as one field of cotton wool.
@export var mid_cloud: float = 0.5
## Horizon haze in the sky shader by day and at dusk (0 clear, 1 milky).
@export var day_haze: float = 0.16
@export var dusk_haze: float = 0.5
@export_group("Twilight")
## The warm band on the horizon and the cool band above it, at sunrise and at sunset. Sunrise is
## pinker and cooler; sunset has the day's dust in it, so it runs redder.
@export var sunrise_warm: Color = Color(1.0, 0.52, 0.34)
@export var sunrise_band: Color = Color(0.38, 0.34, 0.62)
@export var sunset_warm: Color = Color(1.0, 0.40, 0.14)
@export var sunset_band: Color = Color(0.46, 0.26, 0.52)
## How much of the sky the twilight bands paint over the plain gradient (0..1).
@export var twilight_strength: float = 0.85
## Height the warm band decays over, with the sun on the horizon (x) and once it is well down (y).
@export var twilight_height: Vector2 = Vector2(0.17, 0.065)
## Where the cool band sits above the horizon, with the sun on the horizon (x) and well down (y).
@export var twilight_band_height: Vector2 = Vector2(0.30, 0.16)
## Crepuscular rays through the gaps in the cloud deck (0 off). They are gated on `cloud_detail`
## in the shader, so Quality drops them on web and below MEDIUM with the rest of the cloud work.
@export var god_rays: float = 1.1
@export_group("Moon")
## Hours the moon trails the sun. 12 is a full moon rising exactly at sunset; less than that puts
## it up for most of the night as a gibbous, which is a far more interesting shape.
@export var moon_offset_hours: float = 9.5
@export var moon_color: Color = Color(0.94, 0.95, 1.0)
## Apparent radius of the moon in radians. The real one is about 0.0045; a little larger reads
## better on a 16:9 screen without turning into a second sun.
@export var moon_radius: float = 0.012
## Halo around the moon, and the milky-way band brightness at full night.
@export var moon_halo: float = 0.8
@export var milky_way: float = 0.55
@export_group("Exposure")
## Camera exposure by day and at full night. AgX rolls a huge range into the screen, so the
## whole frame sits in a narrow band of grey unless something puts it back: the LUT in the city
## Environment supplies the contrast, and this supplies the level. Opening up after dark is the
## cheap version of eye adaptation - without it the night grade crushes a street lit by lamps
## into mud.
@export var day_exposure: float = 1.25
@export var night_exposure: float = 2.1
@export_group("Distance")
## Colour of the depth fog by day, at dusk and at night. It is deliberately a touch darker and
## less blue than the horizon: fog that is exactly the sky colour erases the far half of the
## frame, which is what "washed out" means when someone says an aerial looks flat.
## The day value is a warm grey, not a blue. It was (0.50, 0.62, 0.76), and every distant pixel
## in a wide shot took that cast - measured, a beach frame averaged 112/127/140 RGB - which read
## as a cold, milky film over the city. Basin haze over a dry coastal city is dust and smog
## lit by the sun; it goes beige, and the sky above it stays the blue.
@export var day_fog: Color = Color(0.63, 0.62, 0.57)
@export var dusk_fog: Color = Color(0.72, 0.45, 0.33)
@export var night_fog: Color = Color(0.05, 0.07, 0.14)
@export_group("")
## Ambient light color and strength by day and by night (moonlight).
@export var day_ambient: Color = Color(0.62, 0.7, 0.85)
@export var night_ambient: Color = Color(0.3, 0.38, 0.6)
## Sky fill in the shadows. Kept well under the sun (see day_sun_energy): a real midday shadow
## is about a fifth as bright as the lit side, not two thirds.
@export var day_ambient_energy: float = 0.30
## Night sky fill. Halved from 0.55 with the moon, for the same reason: at night the city is lit
## by its lamps and windows, and the sky only just shows the shapes between them.
@export var night_ambient_energy: float = 0.3
## Global illumination strength by day and by night. The streets' night glow is emission, and
## SDFGI takes emission as light: at the daytime 0.85 it bounced the orange road glow across
## every pavement and roof round it, so a night aerial read as orange paving under a
## moonlit-day sky. The glow is a stand-in for lamps that are not built there, not a light
## source, so at night the bounce is turned well down.
@export var day_gi_energy: float = 0.85
@export var night_gi_energy: float = 0.3
@export_node_path("DirectionalLight3D") var sun_path: NodePath
@export_node_path("WorldEnvironment") var environment_path: NodePath

## Weather hooks (set by the Weather node every frame): extra cloud cover and how dark it is.
var cloud_extra: float = 0.0
var weather_darken: float = 0.0

## Hour of the day, 0..24.
var hour: float = 9.0
var night_factor: float = 0.0
## How strongly the volumetric haze should read this frame, 1 with the sun on the horizon and a
## third of that with it overhead. Haze is forward scattering through a long path of lit air:
## it is most of what a hazy sunset looks like and almost none of what a hazy noon looks like.
## Weather multiplies the volumetric density by this, so the 900 m volume can carry the basin
## at golden hour without laying a lit white veil over noon.
var haze_gain: float = 1.0
## Directions toward the sun and the moon this frame (the sun's is continuous, so it really sets).
var sun_dir: Vector3 = Vector3.UP
var moon_dir: Vector3 = Vector3.UP

var _sun: DirectionalLight3D
var _env: Environment
## How bright the street lamps burn at full night. Quality scales this down at the low levels.
@export var lamp_energy: float = 2.6
var lamp_scale: float = 1.0
var _lamp_level: float = -1.0
var _lamp_timer: float = 0.0
## The sky's horizon colour this frame, published as the `sky_tint` shader global.
var _horizon_now: Color = Color(0.66, 0.75, 0.88)
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


## The arc a body rides across the sky. `u` is 0 at its rise, 0.5 at its peak and 1 at its set,
## and the basis' +Z points back at the body (a light shines along -Z), so it stays continuous
## below the horizon instead of having to be special-cased at night.
func _arc_basis(u: float) -> Basis:
	var elevation := sin(u * PI)
	var pitch := deg_to_rad(-elevation * 85.0)
	var yaw := deg_to_rad(180.0 * u + sun_rotation_z_degrees)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


## A basis whose +Z points along `d`, for aiming the light at the moon.
func _look_basis(d: Vector3) -> Basis:
	var yaw := atan2(d.x, d.z)
	var pitch := asin(clampf(d.y, -1.0, 1.0))
	return Basis.from_euler(Vector3(-pitch, yaw, 0.0))


func _apply() -> void:
	# Sun elevation: up at 6, peak at 12, down at 18.
	var t := (hour - 6.0) / 12.0 # 0..1 across the day
	var elevation := sin(t * PI) # negative at night
	var daylight := clampf(elevation * 3.0, 0.0, 1.0)
	night_factor = 1.0 - clampf((elevation + 0.05) * 6.0, 0.0, 1.0)
	# Golden hour: about 1.5 h either side of sunrise and sunset. The fade-out under the horizon
	# has to be smooth. `dusk` used to be cut off with a hard `float(elevation > -0.3)` step, which
	# dropped it from 0.22 to 0 in a single frame; every other consumer was hidden from that by
	# `night_factor`, which is already exactly 1.0 there and overrides the dusk lerp, but
	# `twilight_amount` is not, so the warm horizon band blinked off at ~19:10 and on again at
	# ~04:50 - twice every eight minutes of play at the default day length.
	var dusk := clampf(1.0 - absf(elevation) * 2.6, 0.0, 1.0) \
		* smoothstep(dusk_fade_elevation.x, dusk_fade_elevation.y, elevation)
	# How far past the horizon the sun is, 0 on it and 1 in deep twilight.
	var deep := clampf(-elevation * 7.0, 0.0, 1.0)
	# How far into real night the LIGHT is. `night_factor` is 1 the moment the sun is three
	# degrees under the horizon, which is right for switching the street lamps and the windows
	# on and wrong for the light itself: civil twilight is still bright and still warm. Driving
	# the sun's colour, the ambient and the exposure off night_factor washed the whole city
	# lavender at 18:30 and over-exposed it by most of a stop - a blue moon lighting a pink sky.
	var moonlight := smoothstep(0.02, -0.34, elevation)
	haze_gain = lerpf(1.0, 0.30, clampf(elevation, 0.0, 1.0))
	# Where the sun and the moon actually are. The sky shader needs the sun's direction even
	# after it has set (the twilight bands are anchored to it), so it is never special-cased.
	var sun_basis := _arc_basis(t)
	sun_dir = sun_basis.z
	var moon_basis := _arc_basis((hour - 6.0 - moon_offset_hours) / 12.0)
	moon_dir = moon_basis.z
	if _sun:
		# The one directional light is the sun by day and the moon by night. Swapping it over the
		# instant the sun crosses the horizon snapped every shadow in the city round; cross-fade
		# the rotation across the few seconds either side instead.
		var moon_mix := smoothstep(0.06, -0.10, elevation)
		var light_basis := sun_basis
		if moon_mix > 0.001:
			# Moonlight has to arrive from above even once the moon itself has set, or the city
			# is lit from underneath in the small hours.
			var lit := Vector3(moon_dir.x, maxf(moon_dir.y, 0.35), moon_dir.z).normalized()
			var to_moon := _look_basis(lit).get_rotation_quaternion()
			light_basis = Basis(sun_basis.get_rotation_quaternion().slerp(to_moon, moon_mix))
		_sun.basis = light_basis
		_sun.light_color = day_sun_color.lerp(dusk_sun_color, dusk).lerp(night_sun_color, moonlight)
		var flash: float = _sun.get_meta("weather_flash", 0.0)
		_sun.light_energy = lerpf(night_sun_energy, day_sun_energy, daylight) * (1.0 - 0.75 * weather_darken) + flash * 2.5
		# A rainy night's haze is lit by the street lamps, not by a moon behind the cloud. Rain
		# thickens the volumetric fog seventy-fold, and lit by the moonlight fill it hung over
		# the whole street as a pale grey veil, so a rainy night read as a grey dusk.
		_sun.light_volumetric_fog_energy = lerpf(1.0, 0.12, moonlight * clampf(weather_darken * 1.6, 0.0, 1.0))
		if flash > 0.0:
			_sun.light_color = _sun.light_color.lerp(Color(0.85, 0.9, 1.0), clampf(flash, 0.0, 1.0))
		_sun.shadow_enabled = true
	if _sky:
		var horizon := day_horizon.lerp(dusk_horizon, dusk).lerp(night_horizon, night_factor)
		_horizon_now = horizon
		# Overcast by day is grey; overcast over a city at night is the city's own sodium light
		# on the cloud base - dark, and warm low down. The storm colours used to be the daytime
		# grey at every hour, so a rainy night had a pale grey sky and read as dusk.
		var storm_top := Color(0.16, 0.17, 0.2).lerp(night_storm_top, moonlight)
		var storm_horizon := Color(0.3, 0.31, 0.34).lerp(night_storm_horizon, moonlight)
		_sky.set_shader_parameter("sky_top", day_sky_top.lerp(dusk_sky_top, dusk).lerp(night_sky_top, night_factor).lerp(storm_top, weather_darken))
		_sky.set_shader_parameter("sky_horizon", horizon.lerp(storm_horizon, weather_darken))
		_sky.set_shader_parameter("cloud_color", day_cloud.lerp(dusk_cloud, dusk))
		_sky.set_shader_parameter("cloud_coverage", clampf(cloud_coverage + 0.12 * sin(hour * 0.9) + cloud_extra, 0.0, 0.98))
		_sky.set_shader_parameter("cloud_shadow", day_cloud_shadow.lerp(dusk_cloud_shadow, dusk).lerp(Color(0.2, 0.2, 0.24), weather_darken))
		# After dark: moonlit cloud on a clear night, the city's own light on an overcast one.
		var overcast := clampf(weather_darken * 1.6, 0.0, 1.0)
		_sky.set_shader_parameter("night_cloud_light", lerpf(0.12, 0.025, overcast))
		_sky.set_shader_parameter("night_glow", Vector3(0.02, 0.025, 0.04).lerp(night_storm_glow, overcast))
		_sky.set_shader_parameter("mid_amount", clampf(mid_cloud + cloud_extra * 0.6, 0.0, 1.0))
		# Stars on the slow ramp, squared: night_factor is already 1.0 three degrees after sunset,
		# which had a full star field out over a still-lit dusk sky at 18:24.
		_sky.set_shader_parameter("stars", moonlight * moonlight)
		_sky.set_shader_parameter("milky_way", milky_way * (1.0 - weather_darken))
		_sky.set_shader_parameter("haze", lerpf(day_haze, dusk_haze, dusk))
		_sky.set_shader_parameter("sun_glow", lerpf(0.9, 1.6, dusk))
		# The sun's own colour, not the light's: the light turns into the moon after dark.
		_sky.set_shader_parameter("sun_dir", sun_dir)
		_sky.set_shader_parameter("sun_color", day_sun_color.lerp(dusk_sun_color, dusk))
		_sky.set_shader_parameter("moon_dir", moon_dir)
		_sky.set_shader_parameter("moon_tint", moon_color)
		_sky.set_shader_parameter("moon_size", moon_radius)
		_sky.set_shader_parameter("moon_glow", moon_halo * (1.0 - weather_darken * 0.7))
		# Twilight bands. Sunrise runs pinker than sunset, and as the sun drops further the warm
		# band squeezes down onto the horizon while the earth's shadow climbs toward the zenith.
		var morning := hour < 12.0
		_sky.set_shader_parameter("twilight_warm", sunrise_warm if morning else sunset_warm)
		_sky.set_shader_parameter("twilight_band", sunrise_band if morning else sunset_band)
		_sky.set_shader_parameter("twilight_amount", dusk * twilight_strength * (1.0 - weather_darken * 0.8))
		_sky.set_shader_parameter("twilight_falloff", lerpf(twilight_height.x, twilight_height.y, deep))
		_sky.set_shader_parameter("twilight_band_height", lerpf(twilight_band_height.x, twilight_band_height.y, deep))
		# Rays are at their most obvious with a low sun behind broken cloud.
		_sky.set_shader_parameter("god_rays", god_rays * (0.45 + 0.55 * dusk) * (1.0 - night_factor) * (1.0 - weather_darken * 0.6))
		# Under the horizon is the far haze the ground plane fades into, not a grey floor.
		_sky.set_shader_parameter("ground_color", horizon.lerp(Color(0.32, 0.34, 0.37), 0.30))
		# The ground follower's horizon has to wash out into the same colour the sky meets it
		# with, or the land ends in a hard line however good the haze is.
		var streamer := get_parent()
		if streamer and streamer.has_method("set_ground_haze"):
			var hz: Color = horizon.lerp(storm_horizon, weather_darken)
			# A directional light shines along -Z, so +Z points back at the sun.
			streamer.set_ground_haze(hz, _sun.global_transform.basis.z if _sun else Vector3.UP)
	if _env:
		_env.tonemap_exposure = lerpf(day_exposure, night_exposure, moonlight)
		_env.sdfgi_energy = lerpf(day_gi_energy, night_gi_energy, moonlight)
		_env.fog_light_color = day_fog.lerp(dusk_fog, dusk).lerp(night_fog, moonlight)
		# Ambient comes from the sky cubemap, so shadows take the sky's own colour (blue at
		# midday, warm at dusk) instead of a flat grey fill: the single biggest realism win in
		# outdoor lighting. At night the sky is nearly black, so we blend back toward a colour
		# fill so the city does not go pitch dark.
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_sky_contribution = lerpf(1.0, 0.35, moonlight)
		_env.ambient_light_color = day_ambient.lerp(night_ambient, moonlight)
		_env.ambient_light_energy = lerpf(day_ambient_energy, night_ambient_energy, moonlight) * (1.0 - 0.35 * weather_darken)
		# Rain haze is grey by day and, like the cloud above it, lit by the streets at night.
		_env.fog_light_color = _env.fog_light_color.lerp(Color(0.35, 0.37, 0.4).lerp(night_storm_fog, moonlight), weather_darken)
	# Street lamps. Setting hundreds of lights every frame is wasteful, but only refreshing when
	# the value moves leaves every lamp that streamed in since the last change sitting at zero,
	# which is why the streets stayed black the first time. Refresh on a slow tick instead, so
	# newly loaded chunks pick the level up within a third of a second.
	var lamp_factor := maxf(night_factor, weather_darken * 0.85)
	var want := lamp_factor * lamp_energy * lamp_scale
	# _apply() is also called from _ready(), where there is no delta parameter to use.
	_lamp_timer -= get_process_delta_time()
	if _lamp_timer <= 0.0 or absf(want - _lamp_level) > 0.04:
		_lamp_timer = 0.35
		_lamp_level = want
		for light in get_tree().get_nodes_in_group("lamp_light"):
			(light as OmniLight3D).light_energy = want
	RenderingServer.global_shader_parameter_set("night_factor", night_factor)
	RenderingServer.global_shader_parameter_set("lamp_factor", lamp_factor)
	# Published for anything that needs to reflect the sky without owning a copy of it (the
	# ocean, and whatever else wants it): the colour the sky meets the horizon with, and the
	# direction back toward the sun.
	RenderingServer.global_shader_parameter_set("sky_tint", _horizon_now)
	if _sun:
		RenderingServer.global_shader_parameter_set("sun_direction", _sun.global_transform.basis.z)
