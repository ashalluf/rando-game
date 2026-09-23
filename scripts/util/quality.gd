class_name Quality
extends Node
## Adaptive graphics and population quality (owner, 2026-09-20: "it's a little bit laggy",
## then "still super laggy"). Watches the frame rate after the city has streamed in and steps
## down one level at a time until the game runs smoothly. Each level cuts render effects AND
## the crowd / traffic caps, because the populated city is CPU work, not just GPU work:
##   HIGH    everything on (SDFGI global illumination, volumetric fog, depth of field)
##   MEDIUM  no SDFGI, no volumetric fog, no depth of field, shorter shadows
##   LOW     also no indirect light and no reflections; FSR 2.2 upscaling, 60 % of people and cars
##   LOWEST  more aggressive upscaling, no ambient occlusion, 35 % of people and cars
## Antialiasing is temporal at every level: TAA at native resolution on HIGH and MEDIUM, and FSR
## 2.2 (which does its own temporal pass) when upscaling. That is what consoles do, and it looks
## far better than the old bilinear downscale while costing less than native plus MSAA.
## It never steps back up (that would oscillate). Override with `-- --quality=0|1|2|3` on desktop
## or `?quality=N` on the web; the HUD shows the level in use and a frame-time breakdown.

enum Level { HIGH, MEDIUM, LOW, LOWEST }

## Level the desktop build starts at.
##
## HIGH (owner, 2026-09-21: "I need it PS5 level graphics"). Global illumination is the single
## biggest difference between this and a modern-looking game, and it was simply switched off.
## Starting here and letting the stepper fall back costs at most a few seconds of the old
## behaviour on a machine that cannot hold it, and gives every machine that can a far better
## picture. The HUD's quality line (F1 twice) says which level is actually in use.
@export var start_level: Level = Level.HIGH
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
## Most pixels the 3D scene renders per level, whatever the window is; FSR 2.2 scales the frame
## up to the window from there. The game opens maximised, and on a Retina Mac Godot draws every
## physical pixel - 3456 x 2234 on a 16-inch MacBook, 7.7 million, three and a half 1080p frames
## - through SDFGI, SSR, SSIL and volumetric fog, all of them per pixel. So "native" was the most
## expensive thing in the game and the stepper never touched it until LOW. 2.6 million is about
## 2150 x 1210: sharper than 1080p, and on a Retina panel the upscale is invisible.
@export var pixel_budget: PackedFloat32Array = PackedFloat32Array([2600000.0, 2200000.0, 1600000.0, 1100000.0])
## Edge sharpening applied by FSR when upscaling (0 = sharpest).
@export var fsr_sharpness: float = 0.25
## Fraction of the crowd and traffic caps per level.
@export var population: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.6, 0.35])
## Directional shadow reach per level (meters). 320 m used to be the top of the range, which
## meant everything past three blocks was lit but never shadowed - the far half of a rooftop or
## aerial shot had no contrast at all. Four PSSM splits (set in city.tscn) carry the longer
## range without giving up the near detail. HIGH is 500, not 700: measured on a downtown street,
## 700 -> 450 took 800 draw calls and a million triangles out of every frame (the last cascade
## redraws every building out to its edge), and past five blocks the far tiers carry the city.
@export var shadow_distance: PackedFloat32Array = PackedFloat32Array([500.0, 380.0, 220.0, 120.0])

var level: Level = Level.HIGH
## The 3D resolution actually in use (window size times the scale), shown on the HUD.
var render_pixels: Vector2i = Vector2i.ZERO
## Last world offset seen, to drop the measurement window across an origin re-centering.
var _last_offset: Vector3 = Vector3.ZERO
var _env: Environment
var _sun: DirectionalLight3D
var _time: float = 0.0
var _frames: int = 0
var _forced: bool = false
var _base_pedestrians: int = -1
var _base_cars: int = -1
var _base_loop_cars: int = -1
var _base_freeway_cars: int = -1
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
	# Throw the window away across an origin re-centering. The streamer moves every node in the
	# scene by a kilometre, which is a one-off hitch at any quality level - SDFGI re-bakes its
	# cascades, the broadphase rebuilds - and it has nothing to do with whether this machine can
	# hold the level. Counted, it drags the average under min_fps and permanently demotes a
	# machine that was running fine.
	if WorldState.world_offset != _last_offset:
		_last_offset = WorldState.world_offset
		_time = warmup
		_frames = 0
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
		if not viewport.size_changed.is_connected(_apply_scale):
			viewport.size_changed.connect(_apply_scale)
		_apply_scale()
		var cam := viewport.get_camera_3d()
		if cam and cam.attributes is CameraAttributesPractical:
			(cam.attributes as CameraAttributesPractical).dof_blur_far_enabled = level == Level.HIGH


## Resolution the 3D scene renders at: this level's render_scale, capped by its pixel_budget.
## Re-run whenever the window changes size, because the cap depends on it.
func _apply_scale() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var i := int(level)
	var window_px := float(viewport.size.x) * float(viewport.size.y)
	var scale: float = render_scale[i]
	if window_px > 0.0:
		scale = minf(scale, sqrt(pixel_budget[i] / window_px))
	scale = clampf(scale, 0.25, 1.0)
	render_pixels = Vector2i(roundi(viewport.size.x * scale), roundi(viewport.size.y * scale))
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
			_base_freeway_cars = traffic.max_freeway_cars
		traffic.max_cars = maxi(6, roundi(_base_cars * f))
		traffic.max_loop_cars = maxi(10, roundi(_base_loop_cars * f))
		traffic.max_freeway_cars = maxi(8, roundi(_base_freeway_cars * f))
	if _base_props < 0:
		_base_props = PhysicsBudget.max_active_bodies
	PhysicsBudget.max_active_bodies = maxi(120, roundi(_base_props * (1.0 if level <= Level.LOW else 0.5)))
	# Far pedestrians update less often on the low levels.
	Pedestrian.lod_mid = 60.0 if level <= Level.MEDIUM else 35.0
	Pedestrian.lod_far = 140.0 if level <= Level.MEDIUM else 80.0
	Pedestrian.shadow_range = 45.0 if level <= Level.MEDIUM else 20.0


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
