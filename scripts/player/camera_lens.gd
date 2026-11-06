class_name CameraLens
extends Node
## The camera itself (wave 5, docs/HANDOFF.md "The camera lens"): what makes the frame read as a
## photograph rather than a render. CameraPost makes one beside itself under the CameraRig (one
## line), so the city and the test room both get it. Four parts, all on the camera:
##
##   exposure  the eye's adaptation into the dark. Godot meters the frame (the mean of each
##             pixel's brightest channel) and divides `auto_exposure_scale` by it, clamped to the
##             camera's [min, max] sensitivity - and by day every frame, the open noon street as
##             much as the inside of an underpass, meters UNDER the dark limit (measured on
##             Forward+ with tools/camera_lens/lens_probe.gd), so main's adaptation was a constant
##             1.6x gain: walking into a tunnel the frame simply went black (p50 20 of 255). The
##             clamps and Godot's speed stay main's (an open street is untouched, bit for bit),
##             and the lens adds an exposure compensation on `auto_exposure_scale` from an
##             enclosure probe (one ray up, eight round, every `probe_interval`): up to
##             `day_open_gain` under a lid by day (`night_open_gain` at night, where the lamps
##             light a garage), reached slowly going in (`open_seconds`, the eye opening up) and
##             left fast coming out (`close_seconds`: the short blow-out stepping into the sun).
##   flare     toward the sun: a veiling glow round it, six thin aperture spikes, a row of faint
##             hexagonal ghosts on the line through the frame's centre, and a veiling lift of the
##             whole frame when the sun is in or near it (contrast drops shooting into the sun).
##             Drawn in the lens pass (shaders/vignette.gdshader) from `sun_uv`; occluded by
##             what the picture really shows at the sun (one tap of the screen's mip chain, so a
##             tower, a tree or a cloud covers it partly or wholly). Off on the web (`supported`).
##   grain     film grain from the exposure: a camera opened up in the dark shows more of it
##             (`grain_dark_gain` at full gain), shaped like film (triangular noise, strongest in
##             the shadows and mid-tones, none in the highlights).
##   bloom     a wider, softer bloom spread (`GLOW_LEVELS`: a tight core and a long tail, like a
##             real lens's point spread, the same total as Godot's default 3 + 5) on the city's
##             Environment; the threshold and intensity stay DayNight's.
##
## `CAMERA_LENS=0` in the environment is the A/B: none of it, every number as on main.
## Probe (Forward+ under lavapipe): tools/camera_lens/lens_probe.gd. Checks:
## tests/camera_lens_checks.gd.

static var enabled: bool = OS.get_environment("CAMERA_LENS") != "0"

## Godot's glow level weights (levels 1..7). Main's are the defaults: 3 and 5 at 1.0.
const GLOW_LEVELS: Array[float] = [0.0, 0.25, 0.55, 0.45, 0.4, 0.25, 0.1]
const GLOW_LEVELS_OLD: Array[float] = [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0]

@export_group("Exposure")
## Most the camera opens up under a lid by day (x main's gain), and at night.
@export var day_open_gain: float = 2.6
@export var night_open_gain: float = 1.3
## Enclosure (0..1, the probe's) where the compensation starts and where it is full.
@export var open_from: float = 0.3
@export var open_full: float = 0.75
## Seconds (time constant) to open up going into the dark, and to close down coming out.
@export var open_seconds: float = 1.8
@export var close_seconds: float = 0.35
## Seconds between enclosure probes.
@export var probe_interval: float = 0.12
## Reach of the probe's rays (metres): up, then the eight round.
@export var probe_up: float = 16.0
@export var probe_round: float = 14.0

@export_group("Flare")
## Overall strength of the sun flare (0 off).
@export var flare_strength: float = 1.0
## The sun's flare fades out this far (screen heights) outside the frame.
@export var flare_outside: float = 0.25

@export_group("Grain")
## Grain multiplier at full dark gain (the camera opened up as far as it goes).
@export var grain_dark_gain: float = 1.6

## This frame's numbers, for the checks and the HUD: 0..1 how enclosed the camera is, the
## adaptation speed in use, the dark limit, the sun's flare weight.
var enclosure: float = 0.0
## The exposure compensation in use (1 = main's) and the one it is heading for.
var compensation: float = 1.0
var compensation_target: float = 1.0
var flare_now: float = 0.0
## Quality's say (CameraPost.quality_level): no flare at LOWEST.
var flare_allowed: bool = true

var _post: Node
var _day: Node
var _day_lookup: float = 0.0
var _probe_t: float = 0.0
var _base_scale: float = -1.0
var _attrs: CameraAttributesPractical
var _env_done: Environment
var _mat: ShaderMaterial
var _mat_lookup: float = 0.0
var _last_real: int = 0


## True where the sun flare draws: not on the web (every pass counts there) or headless.
static func supported() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless"


## Called by CameraPost._ready(): one per player camera rig.
static func attach(post: Node) -> CameraLens:
	if not enabled or post == null:
		return null
	var lens := CameraLens.new()
	lens.name = "Lens"
	lens._post = post
	post.get_parent().add_child.call_deferred(lens)
	return lens


## The compensation the camera heads for: 1 in the open, up to the hour's gain under a lid.
static func open_target(enclosure_now: float, daylight: float, moonlight: float, day_gain: float,
		night_gain: float, from: float, full: float) -> float:
	var day := clampf(daylight, 0.0, 1.0) * (1.0 - clampf(moonlight, 0.0, 1.0))
	var w := smoothstep(from, full, enclosure_now)
	return lerpf(1.0, lerpf(night_gain, day_gain, day), w)


## One step of the eye toward `target`: slow opening up, fast closing down (log space, so a stop
## takes as long at any level).
static func adapt(current: float, target: float, dt: float, open_s: float, close_s: float) -> float:
	var tau := open_s if target > current else close_s
	var k := 1.0 - exp(-dt / maxf(tau, 0.001))
	return exp(lerpf(log(maxf(current, 0.001)), log(maxf(target, 0.001)), k))


## How strongly the sun flares: up in the sky, through clear air, by day.
static func sun_weight(sun_y: float, weather_darken: float, marine: float) -> float:
	var up := smoothstep(-0.02, 0.06, sun_y)
	return up * clampf(1.0 - weather_darken * 1.4, 0.0, 1.0) * clampf(1.0 - marine * 1.2, 0.0, 1.0)


## 0..1 how far the camera has opened up (for the grain).
static func dark_gain(comp: float, day_gain: float) -> float:
	return clampf((comp - 1.0) / maxf(day_gain - 1.0, 0.001), 0.0, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camera_lens")
	_last_real = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf((now - _last_real) / 1_000_000.0, 0.0, 0.25)
	_last_real = now
	# Probes that render at a fixed frame rate (--fixed-fps) step the clock by the frame.
	if Engine.has_meta("camera_lens_fixed"):
		real_dt = _delta
	if _post and is_instance_valid(_post):
		flare_allowed = int(_post.get("quality_level")) <= 2
	var day := _day_night()
	_apply_glow()
	_update_exposure(day, real_dt)
	_update_lens(day)


func _day_night() -> Node:
	if _day != null and is_instance_valid(_day):
		return _day
	_day = null
	_day_lookup -= 1.0
	if _day_lookup > 0.0:
		return null
	_day_lookup = 60.0
	var found := get_tree().root.find_children("*", "DayNight", true, false)
	if found.size() > 0:
		_day = found[0]
	return _day


func _camera() -> Camera3D:
	var rig := get_parent()
	return rig.get_node_or_null("SpringArm3D/Camera3D") as Camera3D if rig else null


## The city's Environment gets the wider bloom spread once (and back with the A/B).
func _apply_glow() -> void:
	var vp := get_viewport()
	var env: Environment = null
	if vp and vp.world_3d:
		env = vp.world_3d.environment
	var cam := vp.get_camera_3d() if vp else null
	if cam and cam.environment:
		env = cam.environment
	if env == null or env == _env_done:
		return
	_env_done = env
	for i in GLOW_LEVELS.size():
		env.set_glow_level(i, GLOW_LEVELS[i])


func _update_exposure(day: Node, dt: float) -> void:
	var cam := _camera()
	if cam == null:
		return
	var attrs := cam.attributes as CameraAttributesPractical
	if attrs == null:
		return
	if attrs != _attrs:
		_attrs = attrs
		_base_scale = attrs.auto_exposure_scale
	var daylight := 1.0
	var moon := 0.0
	if day:
		daylight = float(day.get("daylight_now"))
		moon = float(day.get("moonlight_now"))
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = probe_interval
		enclosure = _probe(cam)
	compensation_target = open_target(enclosure, daylight, moon, day_open_gain, night_open_gain, open_from, open_full)
	compensation = adapt(compensation, compensation_target, dt, open_seconds, close_seconds)
	var want := _base_scale * compensation
	if absf(attrs.auto_exposure_scale - want) > 0.0005 * _base_scale:
		attrs.auto_exposure_scale = want


## 0..1: a lid overhead counts most, then walls round.
func _probe(cam: Camera3D) -> float:
	var world := cam.get_world_3d()
	if world == null:
		return 0.0
	var space := world.direct_space_state
	if space == null:
		return 0.0
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * probe_up, 1)
	var lid := 0.0
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		lid = 1.0 - clampf((hit.position.y - from.y) / probe_up, 0.0, 1.0) * 0.5
	var walls := 0
	for k in 8:
		var a := TAU * k / 8.0
		q = PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0.0, sin(a)) * probe_round, 1)
		if not space.intersect_ray(q).is_empty():
			walls += 1
	return clampf(lid * 0.65 + walls / 8.0 * 0.35, 0.0, 1.0)


func _lens_material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_mat_lookup -= 1.0
	if _mat_lookup > 0.0:
		return null
	_mat_lookup = 60.0
	for n in get_tree().get_nodes_in_group("lens_layer"):
		var rect := n.get_child(0) as CanvasItem if n.get_child_count() > 0 else null
		if rect and rect.material is ShaderMaterial:
			_mat = rect.material
			return _mat
	var city := get_tree().get_first_node_in_group("city")
	var layer := city.get_node_or_null("Vignette") if city else null
	if layer and layer.get_child_count() > 0:
		_mat = (layer.get_child(0) as CanvasItem).material as ShaderMaterial
	return _mat


func _update_lens(day: Node) -> void:
	var mat := _lens_material()
	if mat == null:
		return
	mat.set_shader_parameter("lens_mode", 1)
	var g := dark_gain(compensation, day_open_gain)
	if day:
		g = maxf(g, float(day.get("moonlight_now")) * 0.6)
	mat.set_shader_parameter("grain_gain", lerpf(1.0, grain_dark_gain, g))
	flare_now = 0.0
	var cam := get_viewport().get_camera_3d()
	if not supported() or not flare_allowed or day == null or cam == null or flare_strength <= 0.0:
		mat.set_shader_parameter("flare_amount", 0.0)
		return
	var sun_dir: Vector3 = day.get("sun_dir")
	var w := sun_weight(sun_dir.y, float(day.get("weather_darken")), float(day.get("marine")))
	var fwd := -cam.global_transform.basis.z
	if w <= 0.001 or fwd.dot(sun_dir) < 0.05:
		mat.set_shader_parameter("flare_amount", 0.0)
		return
	var vp_size := get_viewport().get_visible_rect().size
	var p := cam.unproject_position(cam.global_position + sun_dir * 1000.0)
	var uv := p / vp_size
	var aspect := vp_size.x / maxf(vp_size.y, 1.0)
	# Outside the frame (in screen heights) the flare fades: the sun just off the edge still
	# veils the frame, as it does through a real lens.
	var off := Vector2(maxf(absf(uv.x - 0.5) - 0.5, 0.0) * aspect, maxf(absf(uv.y - 0.5) - 0.5, 0.0))
	var outside := 1.0 - clampf(off.length() / maxf(flare_outside, 0.01), 0.0, 1.0)
	flare_now = w * outside * flare_strength
	var tint: Color = day.get("sun_color_now")
	mat.set_shader_parameter("flare_amount", flare_now)
	mat.set_shader_parameter("sun_uv", uv)
	mat.set_shader_parameter("aspect", aspect)
	mat.set_shader_parameter("sun_tint", Vector3(tint.r, tint.g, tint.b).lerp(Vector3.ONE, 0.35))
