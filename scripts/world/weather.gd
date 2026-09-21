class_name Weather
extends Node
## Weather: clear, overcast, rain and thunderstorms, rolling over in game time. Drives clouds and
## darkening through DayNight, fog on the Environment, rain particles around the player, splash
## rings on the ground, rain on the camera lens and a curtain of rain in the distance, lightning
## that flashes the world as well as the sky (with thunder that arrives late by the distance of
## the strike), streets that soak through and dry out again, grass wind, and the ocean's waves,
## wind and weather darkening through shader globals and the ocean material.
## Debug: ?weather=storm on the web, -- --weather=storm on desktop (clear, overcast, rain, storm).

enum State { CLEAR, OVERCAST, RAIN, STORM }
const STATE_NAMES := ["Clear", "Overcast", "Rain", "Storm"]
## Metres per second sound travels: the gap between a strike and its thunder is this and nothing
## else, so a far strike rumbles many seconds after its flash.
const SOUND_SPEED := 343.0

## Seconds a weather state lasts before rolling again (real seconds).
@export var state_length: Vector2 = Vector2(70.0, 160.0)
## Odds of each state on a roll: clear, overcast, rain, storm.
@export var odds: PackedFloat32Array = PackedFloat32Array([0.42, 0.22, 0.18, 0.18])
## Seconds to blend between states.
@export var blend_seconds: float = 12.0
@export_group("Rain")
@export var rain_amount: int = 1000
@export var storm_rain_amount: int = 1800
@export var rain_wind: Vector3 = Vector3(6.0, 0.0, 2.0)
## Splash rings on the ground: how many are alive at once and how far around the player they land.
@export var splash_amount: int = 170
@export var splash_radius: float = 16.0
## Peak strength of the raindrops running down the camera lens (0 turns them off).
@export var lens_rain: float = 0.85
## The curtain of rain in the distance: how far out it stands, how tall it is, and how opaque it
## gets in a downpour (0 turns it off). It is what makes rain read as weather over the whole city
## rather than as particles following the player about.
@export var curtain_radius: float = 90.0
@export var curtain_height: float = 70.0
@export var curtain_opacity: float = 0.5
@export_group("Wetness")
## Seconds of steady rain to soak the streets through, and seconds of dry weather to dry them out
## again. Drying is much slower than soaking, which is why the city stays shiny after a shower.
@export var soak_seconds: float = 16.0
@export var dry_seconds: float = 80.0
@export_group("Storm")
@export var lightning_gap: Vector2 = Vector2(3.0, 11.0)
## Length of one stroke of a flash (a strike is two to four of them).
@export var flash_seconds: float = 0.14
## How far away a strike can be (metres). The near end cracks at once, the far end rumbles about
## nine seconds later.
@export var strike_distance: Vector2 = Vector2(120.0, 3200.0)
## Peak energy of the lightning's own directional light, which flashes the city itself. The sun
## brightening is not enough: at night it points up from under the horizon and lights nothing.
@export var flash_light_energy: float = 5.5
## Tsunami-scale waves during storms: how big (0 to 1 of the ocean shader's tsunami_height) and
## how often (seconds between them).
@export var tsunami_strength: float = 1.0
@export var tsunami_gap: Vector2 = Vector2(25.0, 60.0)
@export var tsunami_seconds: float = 40.0
@export_group("Waves")
## Wave scale per state (multiplies the ocean shader's base height).
@export var wave_scale_by_state: PackedFloat32Array = PackedFloat32Array([1.0, 1.8, 3.2, 6.0])
@export_group("Fog")
## Depth fog per state. Weather SETS these on the Environment every frame, so whatever
## city.tscn says is only what you see before the first frame - tune here, not there.
## 0.00022 is about 18 km of Koschmieder visibility, a smoggy day; 0.00012 is 33 km, which is
## what a clear LA day looks like, and it is the only term in the whole haze stack with a
## distance gradient in it.
@export var fog_by_state: PackedFloat32Array = PackedFloat32Array([0.00012, 0.0004, 0.0009, 0.0013])
## Volumetric fog per state - and this one was the whole aerial haze problem. Godot clamps the
## froxel lookup at volumetric_fog_length (220 m), so past that distance the volumetric term
## stops growing and becomes a FLAT curtain carrying no distance information at all. At 0.0025
## that curtain was 42 % over everything beyond 220 m, out-weighing the depth fog at every range
## the camera can see and flattening the mountains into silhouettes. At 0.0004 it is an 8 %
## near-field medium - which is what volumetric fog is for - and the depth fog above does the
## distance.
@export var volumetric_by_state: PackedFloat32Array = PackedFloat32Array([0.0004, 0.005, 0.012, 0.02])

var state: State = State.CLEAR
var blend: float = 0.0        # 0 = previous state fully, 1 = current state fully
## Current wave scale and rain level, for the HUD and tests.
var wave_scale: float = 1.0
var rain_level: float = 0.0
## How wet the streets are (0 dry, 1 soaked). Lags the rain: it builds while it rains and dries
## off slowly afterwards, so a shower leaves the city shining for a while.
var wetness: float = 0.0
var _previous: State = State.CLEAR
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _rain: CPUParticles3D
var _splash: CPUParticles3D
var _curtain: MeshInstance3D
var _curtain_mat: ShaderMaterial
var _lens: CanvasLayer
var _lens_rect: ColorRect
var _lens_mat: ShaderMaterial
var _flash_light: DirectionalLight3D
var _player: Node3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _daynight: Node
var _streamer: Node
var _ocean: ShaderMaterial
var _next_flash: float = 5.0
var _thunder_in: float = -1.0
var _strike_dir: Vector3 = Vector3.FORWARD
var _strike_near: float = 1.0
var _pulses: Array[Vector3] = []   # x start, y length, z level of each stroke of a flash
var _pulse_end: float = 0.0
var _strike_age: float = -1.0
var _rain_loop: AudioStreamPlayer3D
var _next_tsunami: float = 12.0
var _tsunami_left: float = 0.0
var _forced: bool = false
var _ground_y: float = 0.0
var _ground_at: Vector3 = Vector3(1.0e9, 0.0, 1.0e9)
var _ground_timer: float = 0.0
var _last_offset: Vector3 = Vector3.ZERO
var _shift_hold: int = 0
var _quality: Node
var _quality_level: int = -1
var _quality_tick: float = 0.0
var _low_detail: bool = false


func _ready() -> void:
	_rng.seed = 4242
	_streamer = get_parent()
	_daynight = get_parent().get_node_or_null("DayNight")
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky:
			_sky = _env.sky.sky_material as ShaderMaterial
	_ocean = PropFactory.ocean_material()
	# Deferred: a child's _ready() runs before its parent's, and CityStreamer._ready() is what
	# creates `plan`, so calling this directly reads null and silently pushes nothing. The shader's
	# defaults happen to match MacroMap's today, which is exactly why this went unnoticed - change
	# a coast number in MacroMap and the surf line would have quietly stayed where it was.
	_push_ocean_shape.call_deferred()
	_build_rain()
	_build_splashes()
	_build_curtain()
	_build_lens()
	_build_flash_light()
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


## Hands the ocean shader the shape of the coast, so it knows where to break its waves. It is the
## same shoreline MacroMap.coast_x() / in_bay() draw; the shader cannot call into GDScript, so the
## numbers are copied across once. Everything coast_x() uses is a MacroMap field and is sent here,
## so the shader's own defaults only matter before this runs (the showroom, a scene with no
## Weather node); the smoke test checks those defaults still match.
func _push_ocean_shape() -> void:
	if _ocean == null:
		return
	var plan: Variant = _streamer.get("plan") if _streamer else null
	var macro: Variant = plan.get("macro") if plan else null
	if macro:
		_ocean.set_shader_parameter("coast_base_x", macro.get("coast_base_x"))
		_ocean.set_shader_parameter("coast_wobble", macro.get("coast_wobble"))
		_ocean.set_shader_parameter("coast_period", macro.get("coast_period"))
		_ocean.set_shader_parameter("peninsula_bulge", macro.get("peninsula_bulge"))
		_ocean.set_shader_parameter("peninsula_center", macro.get("peninsula_center"))
		_ocean.set_shader_parameter("peninsula_radius", macro.get("peninsula_radius"))
		_ocean.set_shader_parameter("bay_z", macro.get("bay_z"))
		_ocean.set_shader_parameter("bay_east_x", macro.get("bay_east_x"))
	var wind := Vector2(rain_wind.x, rain_wind.z)
	if wind.length() < 0.01:
		wind = Vector2(1.0, 0.3)
	_ocean.set_shader_parameter("wind_dir", wind.normalized())


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
	# A raindrop is a streak, not a dash: long and thin reads as falling water, and a longer
	# quad also gives the temporal pass a coherent object to track instead of a cloud of small
	# ones it smears into frosted glass.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.95)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.82, 0.92, 0.38)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	_rain.mesh = quad
	# A thousand alpha quads in the sun's shadow map painted dark streaks down every wall in the
	# city and cost a shadow pass for the privilege. Rain does not cast a shadow you can see.
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


## Rings of splash on whatever the player is standing on. Rain you only see in the air is rain
## falling through the world; the ground has to answer it.
func _build_splashes() -> void:
	if splash_amount <= 0:
		return
	_splash = CPUParticles3D.new()
	_splash.name = "RainSplash"
	_splash.amount = splash_amount / 2 if OS.has_feature("web") else splash_amount
	_splash.lifetime = 0.55
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash.emission_box_extents = Vector3(splash_radius, 0.04, splash_radius)
	_splash.direction = Vector3.UP
	_splash.spread = 0.0
	_splash.gravity = Vector3.ZERO
	_splash.initial_velocity_min = 0.0
	_splash.initial_velocity_max = 0.0
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.2
	# A ring spreading out from nothing. A Curve clamps to max_value (1.0), so the growth lives
	# in scale_amount_max, not in the curve.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.1))
	grow.add_point(Vector2(1.0, 1.0))
	_splash.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	ramp.add_point(0.2, Color(1.0, 1.0, 1.0, 0.75))
	_splash.color_ramp = ramp
	var plane := PlaneMesh.new()   # PlaneMesh lies flat in XZ, which a QuadMesh does not
	plane.size = Vector2(0.55, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _ring_texture()
	mat.albedo_color = Color(0.86, 0.92, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	_splash.mesh = plane
	_splash.emitting = false
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)


## One expanding splash ring, drawn into a small image once: a soft annulus, transparent inside.
func _ring_texture() -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var a := exp(-pow((r - 0.74) / 0.17, 2.0))
			a *= 1.0 - smoothstep(0.86, 1.0, r)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## The wall of rain standing off in the distance: one open cylinder around the player wearing
## sheets of falling streaks, seen from the inside. Fog and particles alone never read as a
## downpour over a whole city, because the particles stop thirty metres out.
func _build_curtain() -> void:
	if curtain_opacity <= 0.001:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = curtain_radius
	cyl.bottom_radius = curtain_radius
	cyl.height = curtain_height
	cyl.radial_segments = 48
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_curtain_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix;

uniform float strength = 0.0;
uniform float height = 70.0;
uniform vec3 tint : source_color = vec3(0.66, 0.72, 0.82);
// Cells per second the streak sheets fall. At 34 cells over a 70 m cylinder this is about
// 14 m/s, which is roughly what rain does; at the old 2.4 it drifted down at walking pace.
uniform float fall = 7.0;

varying vec3 local_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	// Object space, not UV: a CylinderMesh packs its side into half its UV range, and a veil
	// that is silently invisible over half its height is a long afternoon.
	local_pos = VERTEX;
}

void fragment() {
	float up = clamp(local_pos.y / max(height, 0.01) + 0.5, 0.0, 1.0);
	float ang = atan(local_pos.x, local_pos.z);
	// A thin veil, with three sheets of falling streaks laid over it.
	//
	// The cell frequencies decide how big a streak is, and they used to be far too low: 40
	// cells around a 565 m circumference is 2.2 m per streak, and 6 up a 70 m cylinder is
	// 11.7 m, so at the curtain's 90 m radius every "streak" was a soft blob about 18 px wide
	// and 95 px tall. Hundreds of those over the frame is not rain, it is frosted glass, and it
	// was the thing making a storm look like a smeared lens. At these numbers a streak is about
	// 0.35 m by 2 m - three pixels by sixteen at that distance - which is what rain looks like.
	float v = 0.12;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		// PLUS, not minus: a streak sits at a constant cell.y, so up = (const - TIME * fall) / k
		// and the pattern falls. With a minus the streaks climb, and the rain went up the sky.
		vec2 cell = vec2(ang * (260.0 + fi * 140.0), up * (34.0 + fi * 13.0) + TIME * (fall + fi * 0.8));
		float r = hash12(floor(cell) + fi * 17.3);
		float column = 1.0 - abs(fract(cell.x) - 0.5) * 2.0;
		v += smoothstep(0.45, 1.0, r) * column * (0.42 - fi * 0.1);
	}
	// Soft top and bottom, so the cylinder never shows its own rim.
	float band = smoothstep(0.0, 0.25, up) * (1.0 - smoothstep(0.72, 1.0, up));
	ALBEDO = tint;
	ALPHA = clamp(v, 0.0, 1.0) * band * strength;
}
"""
	_curtain_mat.shader = shader
	_curtain_mat.set_shader_parameter("height", curtain_height)
	_curtain = MeshInstance3D.new()
	_curtain.name = "RainCurtain"
	_curtain.mesh = cyl
	_curtain.material_override = _curtain_mat
	_curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_curtain.visible = false
	add_child(_curtain)


## Raindrops on the camera itself, under the HUD (layer -1, the same place the vignette lives).
func _build_lens() -> void:
	if lens_rain <= 0.001:
		return
	_lens_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.80, 0.86, 0.95);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 c = uv * vec2(58.0 + fi * 26.0, 34.0 + fi * 15.0);
		// MINUS, not plus: SCREEN_UV.y runs downward in a canvas_item shader, so subtracting
		// time walks a drop toward the bottom of the frame. Adding it slid them up the glass.
		c.y -= TIME * (0.8 + fi * 0.7);
		float r = hash12(floor(c) + fi * 23.1);
		if (r < 0.86) {
			continue;
		}
		vec2 f = fract(c) - vec2(0.5);
		f.y *= 0.45;   // stretched into a streak running down the glass
		a = max(a, (1.0 - smoothstep(0.1, 0.4, length(f))) * (0.45 + 0.55 * r));
	}
	// Heavier toward the edges of the frame, the way a real lens catches it.
	float edge = 0.5 + 0.95 * length(uv - vec2(0.5));
	COLOR = vec4(tint, clamp(a * edge, 0.0, 1.0) * strength * 0.18);
}
"""
	_lens_mat.shader = shader
	_lens_rect = ColorRect.new()
	_lens_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lens_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens_rect.material = _lens_mat
	_lens_rect.visible = false
	_lens = CanvasLayer.new()
	_lens.name = "RainLens"
	_lens.layer = -1
	_lens.add_child(_lens_rect)
	add_child(_lens)


## Lightning's own light. The sun's energy already jumps on a flash, but the sun is under the
## horizon at night - exactly when a storm is worth looking at - so the city stayed dark while
## the sky lit up. This one comes in from the strike, nearly level, and is off the rest of the time.
func _build_flash_light() -> void:
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.light_color = Color(0.86, 0.90, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_flash_light.visible = false
	add_child(_flash_light)


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	# Skip world queries for a couple of frames after an origin shift; the broadphase lags.
	if _last_offset != WorldState.world_offset:
		_last_offset = WorldState.world_offset
		_shift_hold = 2
	elif _shift_hold > 0:
		_shift_hold -= 1
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
	# The sea is lit by the sky above it, and DayNight publishes the clear-sky horizon colour
	# whatever the weather, so the ocean is told how dark it is here.
	if _ocean:
		_ocean.set_shader_parameter("weather_dark", dark)
		_ocean.set_shader_parameter("world_offset", Vector2(WorldState.world_offset.x, WorldState.world_offset.z))
	# Streets soak through while it rains and dry out slowly afterwards, rather than tracking the
	# rain instantly: a shower that stops does not leave dry tarmac behind it.
	var wet_target := clampf(rain * 1.2, 0.0, 1.0)
	var soak := delta / maxf(soak_seconds, 0.01) if wet_target > wetness else delta / maxf(dry_seconds, 0.01)
	wetness = move_toward(wetness, wet_target, soak)
	PropFactory.set_wetness(wetness)
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
	_quality_tick -= delta
	if _quality_tick <= 0.0:
		_quality_tick = 2.0
		_update_quality()
	_update_splashes(delta, rain)
	if _curtain:
		_curtain.visible = rain > 0.05 and not _low_detail
		if _curtain.visible:
			if _player:
				_curtain.global_position = _player.global_position + Vector3(0.0, curtain_height * 0.28, 0.0)
			_curtain_mat.set_shader_parameter("strength", curtain_opacity * rain)
	if _lens_rect:
		_lens_rect.visible = rain > 0.03 and not _low_detail
		if _lens_rect.visible:
			_lens_mat.set_shader_parameter("strength", lens_rain * rain)
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
			_strike()
			_next_flash = _rng.randf_range(lightning_gap.x, lightning_gap.y)
		_next_tsunami -= delta
		if _next_tsunami <= 0.0 and _tsunami_left <= 0.0:
			_tsunami_left = tsunami_seconds
			_next_tsunami = _rng.randf_range(tsunami_gap.x, tsunami_gap.y)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0 and _player and Sfx.has("thunder"):
			# Where the sound comes from is the strike's direction; how loud and how low it is
			# says how far away it was. The delay above did the same job in time.
			var at := _player.global_position + _strike_dir * 35.0 + Vector3(0.0, 22.0, 0.0)
			Sfx.play("thunder", at, lerpf(-7.0, 9.0, _strike_near), lerpf(0.55, 1.1, _strike_near))
	_update_flash(delta)
	if _tsunami_left > 0.0:
		_tsunami_left -= delta
	var tsunami := 0.0
	if _tsunami_left > 0.0:
		# Ramp in and out over the event.
		var u := 1.0 - _tsunami_left / tsunami_seconds
		tsunami = tsunami_strength * sin(u * PI)
	RenderingServer.global_shader_parameter_set("tsunami_scale", tsunami)


## Rain is not free: from LOW the splash count comes down, and at LOWEST the curtain and the
## drops on the lens go away, the same way Quality trims everything else in the city.
func _update_quality() -> void:
	if _quality == null:
		_quality = get_parent().get_node_or_null("Quality")
	var level: int = int(_quality.get("level")) if _quality else 1
	if level == _quality_level:
		return
	_quality_level = level
	_low_detail = level >= 3
	var want := splash_amount / 2 if OS.has_feature("web") else splash_amount
	if level >= 2:
		want = want * 45 / 100
	if _splash and _splash.amount != want:
		_splash.amount = maxi(1, want)


## Splash rings sit on the ground the player is standing on, not on the player: the height comes
## from one raycast every quarter second (or whenever they have walked out of the patch).
func _update_splashes(delta: float, rain: float) -> void:
	if _splash == null:
		return
	_splash.emitting = rain > 0.05
	if not _splash.emitting or _player == null:
		return
	var p := _player.global_position
	_ground_timer -= delta
	if _ground_timer <= 0.0 or absf(p.x - _ground_at.x) > 6.0 or absf(p.z - _ground_at.z) > 6.0:
		_ground_timer = 0.25
		_ground_at = p
		if _shift_hold <= 0 and _streamer and _streamer.has_method("surface_height_at"):
			_ground_y = _streamer.surface_height_at(p)
	_splash.global_position = Vector3(p.x, _ground_y + 0.04, p.z)


## One strike: a direction, a distance, a flicker of two to four strokes, and thunder on its way.
func _strike() -> void:
	var az := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(strike_distance.x, strike_distance.y)
	_strike_dir = Vector3(cos(az), 0.0, sin(az))
	_strike_near = 1.0 - clampf((dist - strike_distance.x) / maxf(strike_distance.y - strike_distance.x, 1.0), 0.0, 1.0)
	_thunder_in = dist / SOUND_SPEED
	var level := lerpf(0.4, 1.25, _strike_near)
	var t := 0.0
	_pulses.clear()
	for i in _rng.randi_range(2, 4):
		var length := flash_seconds * _rng.randf_range(0.6, 1.5)
		_pulses.append(Vector3(t, length, level * _rng.randf_range(0.55, 1.0)))
		t += length + _rng.randf_range(0.03, 0.12)
	_pulse_end = t
	_strike_age = 0.0


## Runs the flicker: the sky shader's flash, the sun's flash meta (DayNight reads it) and the
## lightning's own light, which is what makes the buildings flash too.
func _update_flash(delta: float) -> void:
	var flash := 0.0
	if _strike_age >= 0.0:
		_strike_age += delta
		for p in _pulses:
			if _strike_age >= p.x and _strike_age < p.x + p.y:
				flash = maxf(flash, p.z * (1.0 - (_strike_age - p.x) / p.y))
		if _strike_age > _pulse_end:
			_strike_age = -1.0
	if _sky:
		_sky.set_shader_parameter("flash", flash)
	if _sun:
		_sun.set_meta("weather_flash", flash)
	if _flash_light:
		_flash_light.visible = flash > 0.001
		if _flash_light.visible:
			var dir := Vector3(-_strike_dir.x, -0.5, -_strike_dir.z).normalized()
			_flash_light.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
			_flash_light.light_energy = flash * flash_light_energy


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
