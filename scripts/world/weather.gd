class_name Weather
extends Node
## Weather: clear, overcast, rain and thunderstorms, rolling over in game time. Drives clouds and
## darkening through DayNight, fog on the Environment, rain particles around the player,
## lightning flashes with thunder, wet roads (PropFactory.set_wetness), grass wind and the
## ocean's wave size through shader globals. Debug: ?weather=storm on the web,
## -- --weather=storm on desktop (clear, overcast, rain, storm).

enum State { CLEAR, OVERCAST, RAIN, STORM }
const STATE_NAMES := ["Clear", "Overcast", "Rain", "Storm"]

## Seconds a weather state lasts before rolling again (real seconds).
@export var state_length: Vector2 = Vector2(70.0, 160.0)
## Odds of each state on a roll: clear, overcast, rain, storm.
@export var odds: PackedFloat32Array = PackedFloat32Array([0.42, 0.22, 0.18, 0.18])
## Seconds to blend between states.
@export var blend_seconds: float = 12.0
@export_group("Rain")
@export var rain_amount: int = 1400
@export var storm_rain_amount: int = 2600
@export var rain_wind: Vector3 = Vector3(6.0, 0.0, 2.0)
@export_group("Storm")
@export var lightning_gap: Vector2 = Vector2(3.0, 11.0)
@export var flash_seconds: float = 0.14
## Tsunami-scale waves during storms: how big (0 to 1 of the ocean shader's tsunami_height) and
## how often (seconds between them).
@export var tsunami_strength: float = 1.0
@export var tsunami_gap: Vector2 = Vector2(25.0, 60.0)
@export var tsunami_seconds: float = 40.0
@export_group("Waves")
## Wave scale per state (multiplies the ocean shader's base height).
@export var wave_scale_by_state: PackedFloat32Array = PackedFloat32Array([1.0, 1.8, 3.2, 6.0])
@export_group("Fog")
@export var fog_by_state: PackedFloat32Array = PackedFloat32Array([0.00022, 0.0004, 0.0009, 0.0013])
@export var volumetric_by_state: PackedFloat32Array = PackedFloat32Array([0.0025, 0.005, 0.012, 0.02])

var state: State = State.CLEAR
var blend: float = 0.0        # 0 = previous state fully, 1 = current state fully
## Current wave scale and rain level, for the HUD and tests.
var wave_scale: float = 1.0
var rain_level: float = 0.0
var _previous: State = State.CLEAR
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _rain: CPUParticles3D
var _player: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _daynight: Node
var _flash_left: float = 0.0
var _next_flash: float = 5.0
var _thunder_in: float = -1.0
var _rain_loop: AudioStreamPlayer3D
var _next_tsunami: float = 12.0
var _tsunami_left: float = 0.0
var _forced: bool = false


func _ready() -> void:
	_rng.seed = 4242
	_daynight = get_parent().get_node_or_null("DayNight")
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	_build_rain()
	_apply_override()
	_timer = _rng.randf_range(state_length.x, state_length.y)
	blend = 1.0


func _apply_override() -> void:
	var text := ""
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&"):
				if part.begins_with("weather="):
					text = part.trim_prefix("weather=")
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--weather="):
				text = arg.trim_prefix("--weather=")
	var idx := ["clear", "overcast", "rain", "storm"].find(text.to_lower())
	if idx >= 0:
		state = idx as State
		_previous = state
		_forced = true


func _build_rain() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_amount
	_rain.lifetime = 1.3
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(34.0, 1.0, 34.0)
	_rain.direction = Vector3(0.0, -1.0, 0.0)
	_rain.spread = 2.0
	_rain.gravity = Vector3(rain_wind.x, -36.0, rain_wind.z)
	_rain.initial_velocity_min = 14.0
	_rain.initial_velocity_max = 18.0
	_rain.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.92, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_rain.mesh = quad
	add_child(_rain)


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	# Roll the weather.
	if not _forced:
		_timer -= delta
		if _timer <= 0.0:
			_roll()
	blend = minf(1.0, blend + delta / blend_seconds)
	# Blended amounts between the previous and current state.
	var rain_prev := _rain_level(_previous)
	var rain_now := _rain_level(state)
	var rain := lerpf(rain_prev, rain_now, blend)
	var cloud := lerpf(_cloud(_previous), _cloud(state), blend)
	var dark := lerpf(_dark(_previous), _dark(state), blend)
	var fog := lerpf(fog_by_state[_previous], fog_by_state[state], blend)
	var vol := lerpf(volumetric_by_state[_previous], volumetric_by_state[state], blend)
	var waves := lerpf(wave_scale_by_state[_previous], wave_scale_by_state[state], blend)
	if _daynight:
		_daynight.set("cloud_extra", cloud)
		_daynight.set("weather_darken", dark)
	if _env:
		_env.fog_density = fog
		_env.volumetric_fog_density = vol
	wave_scale = waves
	rain_level = rain
	RenderingServer.global_shader_parameter_set("wave_scale", waves)
	RenderingServer.global_shader_parameter_set("wind_factor", 1.0 + 3.0 * rain + (2.0 if state == State.STORM else 0.0) * blend)
	PropFactory.set_wetness(clampf(rain * 1.2, 0.0, 1.0))
	# Rain follows the player.
	if _rain:
		# Changing amount restarts the emitter (and turns it on), so only touch it when it changes.
		var want_amount := storm_rain_amount if state == State.STORM else rain_amount
		if _rain.amount != want_amount:
			_rain.amount = want_amount
		_rain.emitting = rain > 0.05
		if _player:
			var vel: Vector3 = _player.get("velocity") if _player.get("velocity") != null else Vector3.ZERO
			_rain.global_position = _player.global_position + Vector3(0.0, 16.0, 0.0) + Vector3(vel.x, 0.0, vel.z) * 0.8 - rain_wind * 0.5
	if rain > 0.05 and _rain_loop == null and Sfx.has("rain"):
		_rain_loop = Sfx.loop_player("rain", -14.0)
		if _rain_loop:
			add_child(_rain_loop)
	if _rain_loop:
		_rain_loop.volume_db = lerpf(-40.0, -8.0, rain)
		if _player:
			_rain_loop.global_position = _player.global_position
	# Lightning and tsunamis during storms.
	var storm := state == State.STORM and blend > 0.5
	if storm:
		_next_flash -= delta
		if _next_flash <= 0.0:
			_flash_left = flash_seconds
			_next_flash = _rng.randf_range(lightning_gap.x, lightning_gap.y)
			_thunder_in = _rng.randf_range(0.4, 2.5)
		_next_tsunami -= delta
		if _next_tsunami <= 0.0 and _tsunami_left <= 0.0:
			_tsunami_left = tsunami_seconds
			_next_tsunami = _rng.randf_range(tsunami_gap.x, tsunami_gap.y)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0 and _player and Sfx.has("thunder"):
			Sfx.play("thunder", _player.global_position + Vector3(_rng.randf_range(-40.0, 40.0), 30.0, _rng.randf_range(-40.0, 40.0)), 6.0, _rng.randf_range(0.7, 1.1))
	var flash := 0.0
	if _flash_left > 0.0:
		_flash_left -= delta
		flash = clampf(_flash_left / flash_seconds, 0.0, 1.0) * 1.2
	if _sky:
		_sky.set_shader_parameter("flash", flash)
	if _sun:
		_sun.set_meta("weather_flash", flash)
	if _tsunami_left > 0.0:
		_tsunami_left -= delta
	var tsunami := 0.0
	if _tsunami_left > 0.0:
		# Ramp in and out over the event.
		var u := 1.0 - _tsunami_left / tsunami_seconds
		tsunami = tsunami_strength * sin(u * PI)
	RenderingServer.global_shader_parameter_set("tsunami_scale", tsunami)


func _roll() -> void:
	_previous = state
	var total := 0.0
	for o in odds:
		total += o
	var r := _rng.randf() * total
	var acc := 0.0
	var next := State.CLEAR
	for i in odds.size():
		acc += odds[i]
		if r <= acc:
			next = i as State
			break
	if next == state:
		next = ((int(state) + 1) % State.size()) as State
	state = next
	blend = 0.0
	_timer = _rng.randf_range(state_length.x, state_length.y)
	if state == State.STORM:
		_next_flash = 2.0
		_next_tsunami = _rng.randf_range(8.0, 20.0)


func state_name() -> String:
	return STATE_NAMES[state]


static func _rain_level(s: State) -> float:
	return [0.0, 0.0, 0.7, 1.0][s]


static func _cloud(s: State) -> float:
	return [0.0, 0.3, 0.42, 0.5][s]


static func _dark(s: State) -> float:
	return [0.0, 0.25, 0.5, 0.72][s]
