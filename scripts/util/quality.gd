class_name Quality
extends Node
## Adaptive graphics quality (owner, 2026-09-20: "it's a little bit laggy"). Watches the frame
## rate after the city has streamed in and steps the heavy effects down one level at a time
## until the game runs smoothly: HIGH is everything, MEDIUM drops global illumination and
## volumetric fog, LOW also drops reflections, ambient occlusion and renders at a lower scale.
## It never steps back up (that would oscillate). Override with `-- --quality=0|1|2` on desktop
## or `?quality=N` on the web; the HUD shows the level in use.

enum Level { HIGH, MEDIUM, LOW }

## Seconds after start before the first measurement (streaming and shader compiling settle).
@export var warmup: float = 8.0
## Length of each measurement window (seconds).
@export var window: float = 4.0
## Average FPS below which the next level down is picked.
@export var min_fps: float = 42.0
## Render scale used at LOW (1.0 = native resolution).
@export var low_render_scale: float = 0.8

var level: Level = Level.HIGH
var _env: Environment
var _sun: DirectionalLight3D
var _time: float = 0.0
var _frames: int = 0
var _forced: bool = false


func _ready() -> void:
	var world_env := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		_env = world_env.environment
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	var forced := _override()
	if forced >= 0:
		_forced = true
		_apply(mini(forced, Level.LOW) as Level)
	elif OS.has_feature("web") or DisplayServer.get_name() == "headless":
		# The web build renders with the Compatibility renderer, which has none of these
		# effects, and the headless check has no frame rate to measure; nothing to adapt.
		set_process(false)


func _process(delta: float) -> void:
	if _forced or level == Level.LOW:
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
		_apply((level + 1) as Level)


func level_name() -> String:
	return ["high", "medium", "low"][level]


func _apply(new_level: Level) -> void:
	level = new_level
	if _env == null:
		return
	match level:
		Level.HIGH:
			pass
		Level.MEDIUM:
			_env.sdfgi_enabled = false
			_env.volumetric_fog_enabled = false
			if _sun:
				_sun.directional_shadow_max_distance = 220.0
		Level.LOW:
			_env.sdfgi_enabled = false
			_env.volumetric_fog_enabled = false
			_env.ssr_enabled = false
			_env.ssao_enabled = false
			if _sun:
				_sun.directional_shadow_max_distance = 160.0
			get_viewport().scaling_3d_scale = low_render_scale
	print("Quality: ", level_name())


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
