class_name SkySettle
extends Node
## The sky's radiance map catches up with a jump at once (docs/HANDOFF.md "The hero in the rain on
## the web"). The city's Sky is PROCESS_MODE_INCREMENTAL: a change re-renders the cubemap and its
## rough levels are filtered again over the following frames. That is the right trade while the
## sky drifts (the hour, the clouds), but after a JUMP - the city loading in a clear sky and then
## the forced weather, the pause menu's hour or weather, photo mode - every glossy surface mirrors
## the OLD sky for dozens of frames. The hero's wet velour and hair (roughness 0.45 / 0.2) mirror
## the radiance's middle levels, so for those frames he read royal blue under a grey rain sky; in a
## browser under SwiftShader (20 s a frame) that lasted minutes, which is how "the hero is blue in
## the rain on the web only" was seen. Here: on a jump the sky is switched to PROCESS_MODE_QUALITY
## (every level filtered in one frame) for `hold_frames`, then back to what it was.
## SKY_SETTLE=0 in the environment (?sky_settle=0 on the web) is the A/B.

## Frames the sky is held at QUALITY after a jump.
@export var hold_frames: int = 3
## Frames after the city loads that always count as a jump (the start-up overrides land in them).
@export var start_frames: int = 6
## An hour change larger than this in one frame is a jump (the day runs ~0.001 h a frame).
@export var hour_jump: float = 0.2
## A cloud cover change larger than this in one frame is a jump.
@export var cover_jump: float = 0.05

var _env: Environment
var _sky_mat: ShaderMaterial
var _day: Node
var _hold: int = 0
var _frames: int = 0
var _mode: int = Sky.PROCESS_MODE_INCREMENTAL
var _held: bool = false
var _last_hour: float = -1.0
var _last_cover: float = -1.0
var _last_weather: int = -1
## How many times the sky was held (tests).
var settles: int = 0


static func enabled() -> bool:
	if OS.has_feature("web"):
		# ?sky_settle=0 on the web (the browser has no environment).
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String and (search as String).contains("sky_settle=0"):
			return false
	return OS.get_environment("SKY_SETTLE") != "0"


func setup(env: Environment, day: Node) -> void:
	_env = env
	_day = day
	if _env and _env.sky:
		_sky_mat = _env.sky.sky_material as ShaderMaterial
		_mode = _env.sky.process_mode
	# The pause menu and photo mode change the hour and the weather with the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000


## Hold the sky at QUALITY for `frames` (anything that changes the sky at once may call it).
func kick(frames: int = -1) -> void:
	_hold = maxi(_hold, hold_frames if frames < 0 else frames)


func _process(_delta: float) -> void:
	if _env == null or _env.sky == null:
		return
	_frames += 1
	if _frames <= start_frames:
		kick()
	var h: float = float(_day.get("hour")) if _day else 0.0
	if _last_hour >= 0.0:
		var dh := absf(h - _last_hour)
		dh = minf(dh, 24.0 - dh)
		if dh > hour_jump:
			kick()
	_last_hour = h
	if _sky_mat:
		var c: Variant = _sky_mat.get_shader_parameter("cloud_coverage")
		if c != null:
			if _last_cover >= 0.0 and absf(float(c) - _last_cover) > cover_jump:
				kick()
			_last_cover = float(c)
	var wx: Node = _day.get_parent().get_node_or_null("Weather") if _day and _day.get_parent() else null
	if wx:
		var s := int(wx.get("state"))
		if _last_weather >= 0 and s != _last_weather:
			kick()
		_last_weather = s
	if _hold > 0:
		_hold -= 1
		if not _held:
			_mode = _env.sky.process_mode
			_env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
			_held = true
			settles += 1
	elif _held:
		_env.sky.process_mode = _mode as Sky.ProcessMode
		_held = false
