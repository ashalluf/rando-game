class_name SkyExtras
extends Node
## What the sky shader needs besides the hour (DayNight makes one as its child): the cumulus
## volume's noise, where the camera truly is, the city's light dome and how dark the sky is over
## the camera, and the high jets whose contrails cross it.
##
## The jets are not AirTraffic's (those fly the basin under 1,500 m, too low and warm for a trail):
## they are airliners passing over at cruise, 9-12 km up, which the sky shader draws as a glint
## at the head of a line. They fly straight across, so each trail is ONE segment: a point of a
## trail aged `a` seconds is where the jet was then, moved downwind since, which for a straight
## track at a steady speed is still a straight line (`_push_trails()`). Nothing else is simulated.

## Cumulus: the deck's base and depth (m), the size of the weather map's tile and the billows (m).
@export var cloud_base: float = 1450.0
@export var cloud_depth: float = 1700.0
## How many jets are over the basin at once, and how far from the camera a passing track may be.
@export var contrail_jets: int = 4
@export var pass_radius: float = 26000.0
## Cruise height range (m) and speed range (m/s).
@export var cruise_height: Vector2 = Vector2(9000.0, 11800.0)
@export var cruise_speed: Vector2 = Vector2(220.0, 255.0)
## How long a trail lasts (s): most fade in a minute or two, some persist and spread for ten.
@export var trail_life: Vector2 = Vector2(45.0, 700.0)
## Wind at cruise height (m/s, xz): what drifts and shears the trails.
@export var high_wind: Vector2 = Vector2(18.0, -6.0)
## The light dome: how bright at full night over downtown (linear, at the horizon), and how much
## of it the rest of the city puts up.
@export var dome_strength: float = 0.08
## Seconds between looks at the map round the camera for the dome and the dark sky.
@export var survey_interval: float = 1.5

const SHAPE_PATH := "res://assets/textures/sky/cloud_shape3d.png"
const WEATHER_PATH := "res://assets/textures/sky/cloud_weather.png"
const MAX_TRAILS := 8

var _sky: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _jets: Array[Dictionary] = []
var _clock: float = 0.0
var _survey_left: float = 0.0
## What the survey found: heading to the city's weight, how much of the horizon it wraps, how
## much city there is round the camera (0..1) and how near downtown it is (0..1).
var _city_dir := Vector2(1.0, 0.0)
var _city_wrap: float = 0.0
var _city_share: float = 0.5
var _downtown: float = 0.0

static var _shape_tex: ImageTexture3D
static var _weather_tex: ImageTexture


func setup(sky: ShaderMaterial, seed_value: int) -> void:
	_sky = sky
	_rng.seed = hash([seed_value, "contrails"])
	var forced := _forced_jets()
	if forced >= 0:
		contrail_jets = forced
	if _sky == null:
		return
	_sky.set_shader_parameter("cloud_base", cloud_base / 1000.0)
	_sky.set_shader_parameter("cloud_depth", cloud_depth / 1000.0)
	if textures():
		_sky.set_shader_parameter("cloud_weather", _weather_tex)
		_sky.set_shader_parameter("cloud_shape", _shape_tex)
		_sky.set_shader_parameter("cloud_volume", 1.0)
	# Start with the jets already mid-crossing, their trails grown, as if the sky had been there.
	for i in contrail_jets:
		_jets.append(_new_jet(true))
	if OS.get_environment("SKY_DEBUG") == "1":
		for j in _jets:
			print("JET ", j)


## The two noise textures, built once from the committed images (false when they are missing).
static func textures() -> bool:
	if _shape_tex and _weather_tex:
		return true
	var shape := load(SHAPE_PATH) as Image
	var weather := load(WEATHER_PATH) as Image
	if shape == null or weather == null:
		return false
	shape = shape.duplicate() as Image
	shape.convert(Image.FORMAT_RGBA8)
	var n := shape.get_width()
	var slices: Array[Image] = []
	for z in shape.get_height() / n:
		slices.append(shape.get_region(Rect2i(0, z * n, n, n)))
	_shape_tex = ImageTexture3D.new()
	_shape_tex.create(Image.FORMAT_RGBA8, n, n, slices.size(), false, slices)
	weather = weather.duplicate() as Image
	weather.convert(Image.FORMAT_RGBA8)
	weather.generate_mipmaps()
	_weather_tex = ImageTexture.create_from_image(weather)
	return true


## CONTRAILS=n in the environment, or -- --contrails=n: a fixed number of jets (stills).
func _forced_jets() -> int:
	var text := OS.get_environment("CONTRAILS")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--contrails="):
			text = arg.trim_prefix("--contrails=")
	return text.to_int() if text.is_valid_int() else -1


func _process(delta: float) -> void:
	if _sky == null:
		return
	_clock += delta
	var cam := get_viewport().get_camera_3d()
	var eye := Vector3.ZERO
	if cam:
		eye = WorldState.to_world(cam.global_position)
	_sky.set_shader_parameter("view_km", eye / 1000.0)
	_survey_left -= delta
	if _survey_left <= 0.0:
		_survey_left = survey_interval
		_survey(Vector2(eye.x, eye.z))
	_push_dome()
	_fly(delta, eye)
	_push_trails(eye)


## Looks at the map on three rings round the camera: which way the city lies and how much of it.
func _survey(at: Vector2) -> void:
	var plan: Variant = get_parent().get_parent().get("plan") if get_parent() and get_parent().get_parent() else null
	if plan == null or plan.get("macro") == null:
		return
	var macro: Object = plan.get("macro")
	var lit := Vector2.ZERO
	var total := 0.0
	var share := 0.0
	var rings := [1500.0, 4500.0, 10000.0]
	var weights := [1.0, 0.6, 0.35]
	for ri in rings.size():
		for k in 16:
			var a := TAU * (float(k) + 0.5 * float(ri)) / 16.0
			var d := Vector2(cos(a), sin(a))
			var zone: int = macro.call("zone_at", at + d * float(rings[ri]))
			# CITY, AIRPORT and PORT are lit; beach, ocean and the hills are not.
			var w: float = weights[ri]
			var city := 1.0 if zone == 0 or zone == 4 or zone == 5 else 0.0
			lit += d * city * w
			share += city * w
			total += w
	var dt: Vector2 = macro.get("downtown_center") - at
	var dist := dt.length()
	_downtown = clampf(1.0 - (dist - 600.0) / 6000.0, 0.0, 1.0)
	# Downtown pulls the dome toward itself: it is the brightest thing in the basin.
	lit += dt.normalized() * (0.8 + 2.0 * _downtown) if dist > 1.0 else Vector2.ZERO
	_city_dir = lit.normalized() if lit.length() > 0.01 else Vector2(1.0, 0.0)
	_city_share = share / maxf(total, 0.001)
	# Standing in it, the city is all round; with it all to one side the dome is a lobe.
	_city_wrap = clampf(1.0 - lit.length() / maxf(share + 0.8 + 2.0 * _downtown, 0.001), 0.0, 1.0) \
		* _city_share


func _push_dome() -> void:
	var lamp := DayNight.lamp_now
	var day := get_parent() as DayNight
	var overcast := clampf(day.weather_darken * 1.6, 0.0, 1.0) if day else 0.0
	# Under cloud the glow is the cloud base lit from below: brighter, and all round.
	var glow := dome_strength * lamp * (0.35 + 0.65 * _city_share + 0.8 * _downtown) * (1.0 + 0.8 * overcast)
	_sky.set_shader_parameter("city_glow", glow)
	_sky.set_shader_parameter("city_dir", _city_dir)
	_sky.set_shader_parameter("city_wrap", lerpf(_city_wrap, 1.0, overcast * 0.6))
	# A dark-sky site has thousands of stars; downtown a few dozen.
	_sky.set_shader_parameter("sky_dark", clampf(1.0 - 0.55 * _city_share - 0.4 * _downtown, 0.08, 1.0))


func _new_jet(grown: bool) -> Dictionary:
	var heading := _rng.randf() * TAU
	var dir := Vector2(cos(heading), sin(heading))
	var side := Vector2(-dir.y, dir.x)
	var speed := _rng.randf_range(cruise_speed.x, cruise_speed.y)
	var life := lerpf(trail_life.x, trail_life.y, pow(_rng.randf(), 1.4))
	# Where along its track it is: a new jet comes in from far out; a grown one is anywhere.
	var along := _rng.randf_range(-60000.0, 25000.0) if grown else -70000.0
	var travelled := 140000.0 if grown else 0.0
	return {
		"offset": side * _rng.randf_range(-pass_radius, pass_radius),
		"along": along,
		"dir": dir,
		"speed": speed,
		"height": _rng.randf_range(cruise_height.x, cruise_height.y),
		"life": life,
		"spread": _rng.randf_range(0.004, 0.013),
		"travelled": travelled,
		"seed": _rng.randf(),
		"anchor": Vector2.ZERO,
		"anchored": false,
	}


func _fly(delta: float, eye: Vector3) -> void:
	var here := Vector2(eye.x, eye.z)
	for i in _jets.size():
		var j := _jets[i]
		if not j.anchored:
			# The track is laid relative to where the camera first saw it, then stays put.
			j.anchor = here
			j.anchored = true
		j.along += j.speed * delta
		j.travelled += j.speed * delta
		if j.along > 75000.0:
			_jets[i] = _new_jet(false)
	while _jets.size() < contrail_jets:
		_jets.append(_new_jet(false))
	while _jets.size() > contrail_jets:
		_jets.pop_back()


func _push_trails(eye: Vector3) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	a.resize(MAX_TRAILS)
	b.resize(MAX_TRAILS)
	c.resize(MAX_TRAILS)
	var n := 0
	for j in _jets:
		if n >= MAX_TRAILS:
			break
		var dir: Vector2 = j.dir
		var head: Vector2 = j.anchor + j.offset + dir * float(j.along)
		# A point of the trail aged t is where the jet was then, blown downwind since:
		# head - (dir * speed - wind) * t. The line it runs back along, and how fast age grows.
		var u: Vector2 = dir * float(j.speed) - high_wind
		var rate := u.length()
		var back := u / maxf(rate, 0.001)
		var length := minf(float(j.travelled), rate * float(j.life) * 4.0)
		var rel := (head - Vector2(eye.x, eye.z)) / 1000.0
		a[n] = Vector4(rel.x, (float(j.height) - eye.y) / 1000.0, rel.y, length / 1000.0)
		# The shader measures distance BEHIND the head, so it gets the way back along the trail.
		b[n] = Vector4(-back.x, -back.y, rate / 1000.0, float(j.life))
		c[n] = Vector4(float(j.speed) / 1000.0, float(j.spread), float(j.seed), 0.0)
		n += 1
	_sky.set_shader_parameter("trail_count", n)
	_sky.set_shader_parameter("trail_a", a)
	_sky.set_shader_parameter("trail_b", b)
	_sky.set_shader_parameter("trail_c", c)
