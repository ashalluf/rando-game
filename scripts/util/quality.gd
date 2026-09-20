class_name Quality
extends Node
## Adaptive graphics and population quality (owner, 2026-09-20: "it's a little bit laggy",
## then "still super laggy"). Watches the frame rate after the city has streamed in and steps
## down one level at a time until the game runs smoothly. Each level cuts render effects AND
## the crowd / traffic caps, because the populated city is CPU work, not just GPU work:
##   HIGH    everything on (SDFGI global illumination, volumetric fog, depth of field)
##   MEDIUM  the desktop default: no SDFGI, no volumetric fog, no depth of field, shorter shadows
##   LOW     also no indirect light and no reflections; FSR 2.2 upscaling, 60 % of people and cars
##   LOWEST  more aggressive upscaling, no ambient occlusion, 35 % of people and cars
## Antialiasing is temporal at every level: TAA at native resolution on HIGH and MEDIUM, and FSR
## 2.2 (which does its own temporal pass) when upscaling. That is what consoles do, and it looks
## far better than the old bilinear downscale while costing less than native plus MSAA.
## It never steps back up (that would oscillate). Override with `-- --quality=0|1|2|3` on desktop
## or `?quality=N` on the web; the HUD shows the level in use and a frame-time breakdown.

enum Level { HIGH, MEDIUM, LOW, LOWEST }

## Level the desktop build starts at (HIGH only when forced with --quality=0).
@export var start_level: Level = Level.MEDIUM
## Seconds after start before the first measurement (streaming and shader compiling settle).
@export var warmup: float = 5.0
## Length of each measurement window (seconds).
@export var window: float = 3.0
## Average FPS below which the next level down is picked.
@export var min_fps: float = 50.0
## Frame-rate cap on desktop (owner: the MacBook ran hot; 60 is what consoles do). 0 = uncapped.
## Not applied in the headless check, where it would slow the test loop.
@export var max_fps: int = 60
## Render scale per level (1.0 = native resolution). Below 1.0 the frame is temporally
## upscaled with FSR 2.2, so it stays sharp.
@export var render_scale: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.75, 0.6])
## Edge sharpening applied by FSR when upscaling (0 = sharpest).
@export var fsr_sharpness: float = 0.25
## Fraction of the crowd and traffic caps per level.
@export var population: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.6, 0.35])
## Directional shadow reach per level (meters).
@export var shadow_distance: PackedFloat32Array = PackedFloat32Array([320.0, 200.0, 140.0, 90.0])

var level: Level = Level.HIGH
var _env: Environment
var _sun: DirectionalLight3D
var _time: float = 0.0
var _frames: int = 0
var _forced: bool = false
var _base_pedestrians: int = -1
var _base_cars: int = -1
var _base_loop_cars: int = -1
var _base_props: int = -1


func _ready() -> void:
	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		_env = world_env.environment
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var headless := DisplayServer.get_name() == "headless"
	if not OS.has_feature("web") and not headless:
		Engine.max_fps = max_fps
	var forced := _override()
	if forced >= 0:
		_forced = true
		apply_level(clampi(forced, 0, Level.LOWEST) as Level)
	elif OS.has_feature("web") or headless:
		# The web build renders with the Compatibility renderer, which has none of these
		# effects, and the headless check has no frame rate to measure; nothing to adapt.
		set_process(false)
	else:
		apply_level(start_level)


func _process(delta: float) -> void:
	if _forced or level == Level.LOWEST:
		set_process(false)
		return
	_time += delta
	if _time < warmup:
		return
	_frames += 1
	if _time < warmup + window:
		return
	var fps := _frames / window
	_time = warmup
	_frames = 0
	if fps < min_fps:
		apply_level((level + 1) as Level)


func level_name() -> String:
	return ["high", "medium", "low", "lowest"][level]


## Applies a level: render effects on the environment, sun and camera, then the population caps.
func apply_level(new_level: Level) -> void:
	level = new_level
	_apply_render()
	_apply_population()
	print("Quality: ", level_name())


func _apply_render() -> void:
	if _env == null:
		return
	var i := int(level)
	_env.sdfgi_enabled = level == Level.HIGH
	_env.volumetric_fog_enabled = level == Level.HIGH
	# Screen-space indirect light (bounce) and reflections are the expensive realism effects.
	_env.ssil_enabled = level <= Level.MEDIUM
	_env.ssr_enabled = level <= Level.MEDIUM
	_env.ssao_enabled = level <= Level.LOW
	# Glow stays on everywhere: it is cheap and it carries most of the filmic look.
	_env.glow_enabled = true
	if _sun:
		_sun.directional_shadow_max_distance = shadow_distance[i]
		_sun.shadow_blur = 1.0 if level <= Level.MEDIUM else 0.7
	# The sky's second cloud layer and its sun-side sampling cost three noise taps per pixel,
	# and the sky fills a lot of an outdoor frame. Drop them once we are stepping quality down,
	# and on the web, where the Compatibility renderer is doing all of this on one thread.
	if _env and _env.sky and _env.sky.sky_material is ShaderMaterial:
		var detail := 1.0 if level <= Level.MEDIUM and not OS.has_feature("web") else 0.0
		(_env.sky.sky_material as ShaderMaterial).set_shader_parameter("cloud_detail", detail)
	# The road shader's second texture fetch, the one that breaks up the tiling, goes with them:
	# roads fill the bottom of every outdoor frame.
	RenderingServer.global_shader_parameter_set("ground_detail",
		1.0 if level <= Level.MEDIUM and not OS.has_feature("web") else 0.0)
	# Real street lamps are the first thing to go when frames get tight; the additive pools of
	# light on the pavement stay, so the street is still readable.
	var dn := get_parent().get_node_or_null("DayNight")
	if dn:
		dn.lamp_scale = 1.0 if level <= Level.MEDIUM else 0.0
	var viewport := get_viewport()
	if viewport:
		var scale: float = render_scale[i]
		viewport.scaling_3d_scale = scale
		# MSAA is redundant next to a temporal pass and costs a lot at these resolutions.
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		viewport.fsr_sharpness = fsr_sharpness
		if scale < 0.999:
			# FSR 2.2 reconstructs the frame from previous ones; it supersedes TAA.
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			viewport.use_taa = false
		else:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.use_taa = true
		var cam := viewport.get_camera_3d()
		if cam and cam.attributes is CameraAttributesPractical:
			(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = level == Level.HIGH


## Scales the crowd, traffic and physics caps and trims what is already there.
func _apply_population() -> void:
	var f := population[int(level)]
	var city := get_parent()
	if _base_pedestrians < 0 and "max_pedestrians" in city:
		_base_pedestrians = city.max_pedestrians
	if _base_pedestrians >= 0:
		city.max_pedestrians = maxi(20, roundi(_base_pedestrians * f))
		if city.has_method("trim_pedestrians"):
			city.trim_pedestrians()
	var traffic := city.get_node_or_null("Traffic")
	if traffic:
		if _base_cars < 0:
			_base_cars = traffic.max_cars
			_base_loop_cars = traffic.max_loop_cars
		traffic.max_cars = maxi(6, roundi(_base_cars * f))
		traffic.max_loop_cars = maxi(10, roundi(_base_loop_cars * f))
	if _base_props < 0:
		_base_props = PhysicsBudget.max_active_bodies
	PhysicsBudget.max_active_bodies = maxi(120, roundi(_base_props * (1.0 if level <= Level.LOW else 0.5)))
	# Far pedestrians update less often on the low levels.
	Pedestrian.lod_mid = 60.0 if level <= Level.MEDIUM else 35.0
	Pedestrian.lod_far = 140.0 if level <= Level.MEDIUM else 80.0


func _override() -> int:
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for part in (search as String).trim_prefix("?").split("&"):
				if part.begins_with("quality="):
					return int(part.trim_prefix("quality="))
		return -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):
			return int(arg.trim_prefix("--quality="))
	return -1
