class_name CameraPost
extends Node
## Cinematic post on the player camera (VISUAL_ROADMAP #12): per-pixel motion blur and the
## depth of field. A child of the CameraRig in player.tscn, so the city and the test room get it.
##
## Motion blur is `MotionBlurEffect` (scripts/util/motion_blur_effect.gd), a CompositorEffect on
## the camera's Compositor. It only exists where the renderer has a RenderingDevice and draws
## Forward+ - never on Compatibility (the web build, the opengl3 stills) or the headless check,
## where it is simply not built. Restrained on purpose: a walk leaves the frame sharp, a boost,
## a fast flight or a car at speed streaks the ground and the buildings, and a camera whip blurs.
## The player and the gun ride with the camera, so they barely move on screen and stay sharp.
## Quality turns it off at LOW / LOWEST (`apply_quality()`). Switches: `-- --motionblur=0`
## (off), `=1` (on), any other number scales the strength; tools set the same through
## `Engine.set_meta("postfx_motion_blur", value)` before the scene loads.
##
## Depth of field is Godot's own far blur on the camera's CameraAttributesPractical (the same
## resource carries the auto exposure; only the dof_* fields are touched here). Three states,
## eased on the REAL clock (the weapon wheel slows time):
##   ambient  the old lens look - a faint far blur past `dof_ground_distance` that opens out with
##            altitude, so an aerial shot stays sharp (HIGH only)
##   aim      holding aim (LockOn): a gentle far blur just past the locked target, or past what
##            the crosshair is on, so the target stands out (HIGH and MEDIUM)
##   wheel    the weapon wheel open: the world past the player goes soft (HIGH and MEDIUM)
## Compatibility has no depth of field at all; setting the fields there is harmless.

@export_group("Motion blur")
## Master switch for the per-pixel motion blur (Forward+ only).
@export var motion_blur_enabled: bool = true
## Multiplies the blur length. 1 is a real camera at `shutter`; 0.5 halves every streak.
@export_range(0.0, 3.0) var motion_blur_strength: float = 1.0
## Fraction of a 1 / `reference_fps` frame the virtual shutter is open (0.5 = the film look).
## The blur is scaled to this exposure whatever the real frame rate is.
@export_range(0.0, 1.0) var shutter: float = 0.5
## The frame rate the exposure is measured against (seconds open = shutter / reference_fps).
@export var reference_fps: float = 60.0
## Longest streak, in pixels of a 1080-line frame (scaled to the real resolution).
@export var max_blur_px: float = 40.0
## Streak length (1080-line pixels) that is dropped before any blur shows, so walking pace and
## small camera moves stay crisp. The blur grows smoothly from zero past it.
@export var velocity_threshold_px: float = 3.0
## Taps per pixel along the streak (8-16 is plenty under TAA).
@export_range(4, 32) var samples: int = 12
## Depth difference, as a fraction of the distance, inside which two pixels count as one
## surface. Smaller keeps a sharp foreground edge from mixing with the background behind it.
@export var depth_tolerance: float = 0.06
## A camera that jumps further than this in one frame (a respawn, an origin re-centre) skips
## the blur for that frame instead of smearing the whole picture (metres).
@export var max_camera_jump: float = 30.0

@export_group("Ambient focus")
## Depth-of-field far distance with the camera at ground level (metres).
@export var dof_ground_distance: float = 260.0
## Extra far distance per metre of altitude. At 150 m up this puts the focus beyond the far
## side of the basin, which is what an aerial shot needs.
@export var dof_altitude_gain: float = 14.0
## How quickly the focus follows a change in altitude. Slow on purpose: a focus that snaps as
## you clear a rooftop is more distracting than the blur it is fixing.
@export var dof_lerp_speed: float = 1.6
## Blur amount of the ambient far blur (Godot's dof_blur_amount: 64 px radius at 1.0).
@export var dof_amount: float = 0.04

@export_group("Aim focus")
## Far blur while holding aim (LockOn).
@export var aim_dof_enabled: bool = true
## Blur amount while aiming (0.06 = a 4 px radius at full blur).
@export var aim_dof_amount: float = 0.06
## The far blur starts this fraction of the focus distance past the target ...
@export var aim_dof_margin: float = 0.35
## ... and never closer than this many metres past it.
@export var aim_dof_margin_min: float = 4.0
## Distance over which the blur ramps to full, as a fraction of the focus distance (and a floor
## in metres).
@export var aim_dof_transition: float = 1.0
@export var aim_dof_transition_min: float = 10.0
## Focus distance when the crosshair is on the sky (metres).
@export var aim_dof_no_hit_focus: float = 150.0
## How fast the focus follows the target or the crosshair (per second, exponential).
@export var aim_focus_speed: float = 8.0

@export_group("Wheel focus")
## Far blur while the weapon wheel is open.
@export var wheel_dof_enabled: bool = true
## Where the wheel's blur starts (metres from the camera; the player stands ~6.5 m away).
@export var wheel_dof_distance: float = 8.0
## Distance over which it ramps to full (metres).
@export var wheel_dof_transition: float = 14.0
## Blur amount with the wheel open (0.16 = a 10 px radius).
@export var wheel_dof_amount: float = 0.16

@export_group("Easing")
## Seconds (real time) to blend into and out of the aim focus.
@export var aim_ease_seconds: float = 0.25
## Seconds (real time) to blend into and out of the wheel blur (the wheel's own slow-motion
## ease is 0.15 s).
@export var wheel_ease_seconds: float = 0.15

@export_group("Debug")
## Seconds a frame counts as for the motion blur; 0 = the real frame time. Tools that render a
## frame every few seconds set 1/60 to see what the Mac shows.
@export var fixed_frame_seconds: float = 0.0

## Quality's say (apply_quality): motion blur, the ambient far blur, the aim / wheel blur.
var motion_blur_allowed: bool = true
var ambient_dof_allowed: bool = true
var focus_dof_allowed: bool = true
## The effect on the camera's Compositor, or null where the renderer cannot run it.
var effect: MotionBlurEffect

var _camera: Camera3D
var _player: Player
var _wheel: Node
var _wheel_lookup: float = 0.0
var _override: float = -1.0
var _last_offset := Vector3.ZERO
var _ambient_distance: float = 260.0
var _focus: float = 30.0
var _aim_w: float = 0.0
var _wheel_w: float = 0.0
var _was_aiming: bool = false
var _last_real: int = 0


func _ready() -> void:
	# Keeps easing (on the real clock) through the pause menu and the wheel's slow motion.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("camera_post")
	var rig := get_parent()
	_camera = rig.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	_player = rig.get_parent() as Player
	_ambient_distance = dof_ground_distance
	_override = _read_override()
	_last_offset = WorldState.world_offset
	_last_real = Time.get_ticks_usec()
	if _camera and supported():
		effect = MotionBlurEffect.new()
		var compositor := Compositor.new()
		compositor.compositor_effects = [effect]
		_camera.compositor = compositor
	_push_motion_blur(1.0 / 60.0)


## True where the motion blur can run: Forward+ with a RenderingDevice (not Compatibility, not
## the web, not the headless dummy renderer).
static func supported() -> bool:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return false
	if RenderingServer.get_rendering_device() == null:
		return false
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## Called by Quality whenever the level changes (0 HIGH .. 3 LOWEST).
func apply_quality(level: int) -> void:
	motion_blur_allowed = level <= 1
	ambient_dof_allowed = level == 0
	focus_dof_allowed = level <= 1


## True while the motion blur is really drawing (the HUD's quality line reads it).
func motion_blur_active() -> bool:
	return effect != null and effect.enabled and effect.ready


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf((now - _last_real) / 1_000_000.0, 0.0, 0.25)
	_last_real = now
	# The frame the renderer is about to draw covers this process step. Godot's delta is scaled
	# by Engine.time_scale, and the blur should see the slowed world move slowly (the wheel), so
	# the exposure is set against the unscaled step.
	var frame := delta / maxf(Engine.time_scale, 0.001)
	if fixed_frame_seconds > 0.0:
		frame = fixed_frame_seconds
	_push_motion_blur(frame)
	_update_focus(real_dt)


func _push_motion_blur(frame_seconds: float) -> void:
	if effect == null:
		return
	var strength := motion_blur_strength * (_override if _override > 0.0 else 1.0)
	effect.enabled = motion_blur_enabled and motion_blur_allowed and _override != 0.0 \
			and strength > 0.0 and shutter > 0.0
	effect.strength = strength
	effect.shutter = shutter
	effect.reference_fps = reference_fps
	effect.max_blur_px = max_blur_px
	effect.threshold_px = velocity_threshold_px
	effect.samples = samples
	effect.soft_z = depth_tolerance
	effect.max_camera_jump = max_camera_jump
	effect.frame_seconds = frame_seconds
	# An origin re-centre moves the camera and the whole world by a kilometre in one frame.
	if WorldState.world_offset != _last_offset:
		_last_offset = WorldState.world_offset
		effect.cut = true


# --- Depth of field -----------------------------------------------------------------------

func _update_focus(real_dt: float) -> void:
	if _camera == null:
		return
	var attrs := _camera.attributes as CameraAttributesPractical
	if attrs == null:
		return
	# Ambient: pushed out with altitude. On the ground a far blur past `dof_ground_distance`
	# reads as a lens and gives the street depth; in the air everything is past that distance
	# and the city would go soft, so the focus opens out with the height above the ground.
	var ground := 0.0
	var city := get_tree().get_first_node_in_group("city")
	if city and city.has_method("ground_height_at"):
		ground = city.ground_height_at(_camera.global_position)
	var altitude := maxf(_camera.global_position.y - ground, 0.0)
	var want := dof_ground_distance + altitude * dof_altitude_gain
	_ambient_distance = lerpf(_ambient_distance, want, 1.0 - exp(-dof_lerp_speed * real_dt))

	var aiming := focus_dof_allowed and aim_dof_enabled and _player != null \
			and _player.lock_on != null and _player.lock_on.aiming
	var wheel := focus_dof_allowed and wheel_dof_enabled and _wheel_open()
	_aim_w = move_toward(_aim_w, 1.0 if aiming else 0.0, real_dt / maxf(aim_ease_seconds, 0.001))
	_wheel_w = move_toward(_wheel_w, 1.0 if wheel else 0.0, real_dt / maxf(wheel_ease_seconds, 0.001))
	if aiming:
		var target := _aim_distance()
		# Snap on the first frame of aim (there is no old focus worth easing from), ease after.
		_focus = target if not _was_aiming else lerpf(_focus, target, 1.0 - exp(-aim_focus_speed * real_dt))
	_was_aiming = aiming

	var far := _ambient_distance
	var transition := _ambient_distance
	var amount := dof_amount if ambient_dof_allowed else 0.0
	if _aim_w > 0.0:
		var e := smoothstep(0.0, 1.0, _aim_w)
		var aim_far := _focus + maxf(aim_dof_margin_min, _focus * aim_dof_margin)
		far = exp(lerpf(log(far), log(aim_far), e))
		transition = lerpf(transition, maxf(aim_dof_transition_min, _focus * aim_dof_transition), e)
		amount = lerpf(amount, aim_dof_amount, e)
	if _wheel_w > 0.0:
		var e := smoothstep(0.0, 1.0, _wheel_w)
		far = exp(lerpf(log(far), log(wheel_dof_distance), e))
		transition = lerpf(transition, wheel_dof_transition, e)
		amount = lerpf(amount, wheel_dof_amount, e)
	attrs.dof_blur_far_enabled = amount > 0.001
	attrs.dof_blur_far_distance = far
	attrs.dof_blur_far_transition = transition
	attrs.dof_blur_amount = amount


## Metres from the camera to what the aim is on: the locked target's chest, else the crosshair.
func _aim_distance() -> float:
	var lock := _player.lock_on
	if lock.target != null and is_instance_valid(lock.target):
		return clampf(_camera.global_position.distance_to(lock.aim_point()), 1.0, 1000.0)
	var aim := _player.get_aim()
	if aim.collider == null:
		return aim_dof_no_hit_focus
	return clampf(_camera.global_position.distance_to(aim.point), 1.0, aim_dof_no_hit_focus)


func _wheel_open() -> bool:
	if _wheel == null or not is_instance_valid(_wheel):
		_wheel = null
		_wheel_lookup -= 1.0
		if _wheel_lookup > 0.0:
			return false
		_wheel_lookup = 30.0 # frames between lookups while there is no wheel (the test room has one)
		_wheel = get_tree().get_first_node_in_group("weapon_wheel")
		if _wheel == null:
			return false
	return _wheel.has_method("is_open") and bool(_wheel.call("is_open"))


func _read_override() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--motionblur="):
			return maxf(float(arg.trim_prefix("--motionblur=")), 0.0)
	if Engine.has_meta("postfx_motion_blur"):
		return maxf(float(Engine.get_meta("postfx_motion_blur")), 0.0)
	return -1.0
