class_name StuntDirector
extends Node
## The stunt moment (StuntRamps): the player (on foot or at the wheel) leaving any stunt lip fast
## and getting properly airborne slows the world down while the jump lasts, like the weapon wheel
## does - Engine.time_scale and the audio eased on the REAL clock (the process delta is itself
## scaled) - and the camera opens a few degrees (CameraRig.camera_fov). It lets go on touch-down,
## after `max_seconds` of real time, or the moment anything else takes the time scale (the wheel,
## photo mode, the downed collapse, a tool's freeze): it then neither restores nor fights it.
## Also the loop's grip: a car in a loop is pressed onto its track and steered along its centre
## line (a VehicleBody3D's wheels have no downforce, and the loop shifts sideways over the turn).
## ONE node under the tree root, made by the first stunt piece a FULL chunk builds (ensure()).
## STUNT_SLOWMO=0 in the environment: the pieces stay, the slow motion does not.

## Engine.time_scale at the height of a jump.
@export_range(0.05, 1.0) var slow_time_scale: float = 0.3
## The audio's playback speed at the height of a jump.
@export_range(0.1, 1.0) var slow_audio_scale: float = 0.55
## Seconds (real) to ease in and out.
@export var ease_in_seconds: float = 0.18
@export var ease_out_seconds: float = 0.3
## The longest the world stays slow (real seconds).
@export var max_seconds: float = 2.6
## Speed (m/s) along the lip's forward needed to count as a launch.
@export var min_launch_speed: float = 11.0
## How long (physics seconds) after crossing a lip the body may still be on the ground and count.
@export var arm_seconds: float = 0.7
## Airborne for this long (physics seconds) before the world slows.
@export var air_before: float = 0.12
## Degrees the camera opens at the height of the moment.
@export var fov_kick: float = 9.0
## The loop's grip (m/s^2 onto the track) and its pull toward the centre line (1/s^2).
@export var loop_grip: float = 16.0
@export var loop_centre: float = 6.0

static var enabled_slowmo: bool = OS.get_environment("STUNT_SLOWMO") != "0"
static var _inst: StuntDirector = null
## Registered pieces: instance id of the pivot -> {"node", "site", "xf" (true world), "lips"}.
static var _sites: Dictionary = {}
## Moments the director has run (checks and probes read it).
static var moments: int = 0
static var last_launch_id: String = ""

var _armed_at: float = -100.0
var _armed_dir := Vector3.ZERO
var _air: float = 0.0
var _ground: float = 0.0
var _active: bool = false
var _slow: float = 0.0
var _owns: bool = false
var _applied: float = 1.0
var _applied_audio: float = 1.0
var _real_start: int = 0
var _fov_added: float = 0.0
var _rig: Node = null
var _clock: float = 0.0
var _body_id: int = 0


static func ensure(ch: Node) -> void:
	if _inst != null and is_instance_valid(_inst):
		return
	var tree := ch.get_tree() if ch.is_inside_tree() else Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_inst = StuntDirector.new()
	_inst.name = "StuntDirector"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> StuntDirector:
	return _inst if _inst != null and is_instance_valid(_inst) else null


static func register(pivot: Node3D, s: Dictionary) -> void:
	var id := pivot.get_instance_id()
	_sites[id] = {"node": pivot, "site": s, "xf": StuntBuild.xform(s), "lips": StuntRamps.lips(s)}
	pivot.tree_exiting.connect(func() -> void: _sites.erase(id), CONNECT_ONE_SHOT)


static func site_count() -> int:
	return _sites.size()


func _exit_tree() -> void:
	_release()
	if _inst == self:
		_inst = null


func _ready() -> void:
	process_priority = 900


# --- Watching ------------------------------------------------------------------------------------

## The body the player is in: the car he drives, or himself.
func _body() -> Node3D:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return null
	var car: Variant = p.get("vehicle")
	if car != null and is_instance_valid(car):
		return car
	return p


func _velocity(b: Node3D) -> Vector3:
	if b is RigidBody3D:
		return (b as RigidBody3D).linear_velocity
	if b is CharacterBody3D:
		return (b as CharacterBody3D).velocity
	return Vector3.ZERO


func _airborne(b: Node3D) -> bool:
	if b is Vehicle:
		return (b as Vehicle).is_airborne()
	if b is CharacterBody3D:
		return not (b as CharacterBody3D).is_on_floor()
	return false


func _physics_process(delta: float) -> void:
	var b := _body()
	if b == null or _sites.is_empty():
		_air = 0.0
		return
	if b.get_instance_id() != _body_id:
		_body_id = b.get_instance_id()
		_armed_at = -100.0
		_active = false
	watch(WorldState.to_world(b.global_position), _velocity(b), _airborne(b), delta, b as Vehicle)


## One physics tick of the watch: the body at true world `p` moving at `v`, in the air or not
## (`car` the player's car, or null on foot). Starts the moment after a launch off a lip.
func watch(p: Vector3, v: Vector3, air: bool, delta: float, car: Vehicle = null) -> void:
	_clock += delta
	if car != null and not is_instance_valid(car):
		car = null
	_air = _air + delta if air else 0.0
	_ground = 0.0 if air else _ground + delta
	for id: int in _sites:
		var e: Dictionary = _sites[id]
		var xf: Transform3D = e.xf
		if (xf.origin - p).length_squared() > 60.0 * 60.0:
			continue
		var local := xf.affine_inverse() * p
		for lip: Array in e.lips:
			var at: Vector3 = lip[0]
			var fwd: Vector3 = (xf.basis * (lip[1] as Vector3)).normalized()
			var hw := float(lip[2]) * 0.5 + 0.8
			var d := local - at
			if absf(d.x) > hw or d.z < -3.5 or d.z > 2.5 or d.y < -2.0 or d.y > 3.5:
				continue
			if v.dot(fwd) >= min_launch_speed:
				_armed_at = _clock
				_armed_dir = fwd
				last_launch_id = String((e.site as Dictionary).id)
		if car != null and int((e.site as Dictionary).kind) == StuntRamps.Kind.LOOP:
			_loop_grip(car, e, local, delta)
	if not _active and air and _air >= air_before and _clock - _armed_at <= arm_seconds + _air and v.length() >= min_launch_speed * 0.8:
		_start()
	elif _active and _ground > 0.06:
		_active = false


## Presses a car in the loop onto its track and toward its centre line.
func _loop_grip(car: Vehicle, e: Dictionary, local: Vector3, delta: float) -> void:
	var s: Dictionary = e.site
	var r: float = s.r
	var rel := Vector2(local.z, local.y - r)
	var dist := rel.length()
	if dist < r - 3.2 or dist > r + 0.8 or local.y < 0.4:
		return
	var phi := atan2(rel.x, -rel.y)
	if phi < 0.0:
		phi += TAU
	var centre := StuntKit.loop_point(r, float(s.shift), phi)
	if absf(local.x - centre.x) > float(s.w):
		return
	var basis: Basis = (e.xf as Transform3D).basis
	var out := basis * (-StuntKit.loop_normal(phi))
	var v := car.linear_velocity
	if v.length() < 6.0:
		return
	var push := out * loop_grip + basis.x * (centre.x - local.x) * loop_centre
	car.apply_central_impulse(push * car.mass * delta)


# --- The moment ----------------------------------------------------------------------------------

func _start() -> void:
	if not enabled_slowmo or not is_inside_tree() or get_tree().paused:
		return
	# Someone else holds the time scale (the wheel, photo mode, the collapse): leave it alone.
	if not _owns and not is_equal_approx(Engine.time_scale, 1.0):
		return
	_active = true
	_real_start = Time.get_ticks_msec()
	moments += 1


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := minf(float(now - _last_ms) / 1000.0, 0.1) if _last_ms > 0 else 0.0
	_last_ms = now
	if _active and float(now - _real_start) / 1000.0 > max_seconds:
		_active = false
	if get_tree().paused:
		return
	# Someone took the time scale over since we last wrote it: let go without restoring.
	if _owns and not is_equal_approx(Engine.time_scale, _applied):
		_owns = false
		_active = false
		_slow = 0.0
		_unkick_fov()
		return
	var target := 1.0 if _active else 0.0
	var rate := ease_in_seconds if _active else ease_out_seconds
	_slow = move_toward(_slow, target, dt / maxf(rate, 0.001))
	if _slow <= 0.0:
		_release()
		return
	if not _owns and not is_equal_approx(Engine.time_scale, 1.0):
		_slow = 0.0
		return
	var e := _slow * _slow * (3.0 - 2.0 * _slow)
	_applied = lerpf(1.0, slow_time_scale, e)
	_applied_audio = lerpf(1.0, slow_audio_scale, e)
	Engine.time_scale = _applied
	AudioServer.playback_speed_scale = _applied_audio
	_owns = true
	_kick_fov(e)


var _last_ms: int = 0


func _release() -> void:
	if _owns:
		if is_equal_approx(Engine.time_scale, _applied):
			Engine.time_scale = 1.0
		if is_equal_approx(AudioServer.playback_speed_scale, _applied_audio):
			AudioServer.playback_speed_scale = 1.0
	_owns = false
	_applied = 1.0
	_applied_audio = 1.0
	_unkick_fov()


func _kick_fov(e: float) -> void:
	if fov_kick <= 0.0:
		return
	var p := get_tree().get_first_node_in_group("player")
	var rig: Variant = p.get("camera_rig") if p != null else null
	if rig == null or not is_instance_valid(rig) or (rig as Object).get("camera_fov") == null:
		return
	if _rig != rig:
		_unkick_fov()
		_rig = rig
	var want := fov_kick * e
	(rig as Object).set("camera_fov", float((rig as Object).get("camera_fov")) + want - _fov_added)
	_fov_added = want


func _unkick_fov() -> void:
	if _rig != null and is_instance_valid(_rig) and _fov_added != 0.0:
		_rig.set("camera_fov", float(_rig.get("camera_fov")) - _fov_added)
	_fov_added = 0.0


## True while the world is slowed by a stunt.
func is_active() -> bool:
	return _active or _owns


## Ends any moment at once and gives the time scale back (tests, teleports).
func reset() -> void:
	_active = false
	_slow = 0.0
	_armed_at = -100.0
	_release()
