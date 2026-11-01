class_name BuskWatcher
extends Pedestrian
## Somebody standing to watch a street performer (Buskers): the ring round a breakdancer, the
## couple in front of a mariachi trio. A crowd rig at a spot facing the act, in the crowd cap and
## the "pedestrian" group (shot, knocked, frightened like anyone; they come back when the scare is
## over and the act is still on). They look at the performer, fold their arms, nod along, and clap
## when the performer finishes a song or lands a freeze (Busker.applause_until_ms): both hands
## brought together in front of the chest by the performer's own arm solve.

var home := Vector2.ZERO
var home_yaw: float = 0.0
var performer: Busker
var _cw: float = 0.0
var _beat: float = 0.0
var _phase: float = 0.0


func setup_watch(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float) -> void:
	setup(block_rect, 4.0, seed_value)
	home = at
	home_yaw = yaw
	_phase = float(absi(seed_value) % 1000) / 1000.0


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	if _carry == CrowdLife.Carry.BAG or _carry == CrowdLife.Carry.SMOKE:
		_carry = CrowdLife.Carry.NONE


func _ready() -> void:
	super()
	# Watching an act is not part of the crowd's rain behaviour (RainCrowd).
	rain = null
	_work(true)


func _work(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 3.0
	_life_base = CrowdLife.IDLE if _life_ok else ""
	if at_once:
		_place_at(home, home_yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(home)


func _life_range_changed(_near: bool) -> void:
	pass


func _act_on() -> bool:
	return performer != null and is_instance_valid(performer) and not performer._down


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE and _act_on():
		_work(false)


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	if not _act_on():
		# The act is gone (shot, run off for good): wander off.
		_end_act()
		return
	_life_look = performer.global_position + Vector3.UP * 1.3 * performer._visual.scale.y
	_beat -= delta
	if _beat <= 0.0 and _one_shot_left <= 0.0:
		_beat = 3.0 + _life.randf() * 6.0
		var r := _life.randf()
		if r < 0.3:
			_one_shot(CrowdLife.NOD)
		else:
			_life_base = CrowdLife.FOLD if r < 0.55 else CrowdLife.IDLE
			_life_clip = _life_base


func _clapping() -> bool:
	return _act_on() and _stage == Stage.DOING and _act == CrowdLife.Act.STAND and _panic_left <= 0.0 \
		and _life_now_ms() < performer.applause_until_ms


func _life_pose(delta: float) -> void:
	super(delta)
	if _head_skel == null or not _life_near:
		_cw = 0.0
		return
	_cw = move_toward(_cw, 1.0 if _clapping() else 0.0, delta * 4.0)
	if _cw <= 0.001:
		return
	var sk := _head_skel
	var u := _skel_unit
	var chest := sk.get_bone_global_pose(sk.find_bone("Spine")).origin
	var clap := 0.5 + 0.5 * sin((float(_life_now_ms()) * 0.001 + _phase) * TAU * 2.6)
	var mid := chest + Vector3(0.0, -0.02, 0.3) * u
	var gap := (0.012 + 0.07 * clap) * u
	var w := smoothstep(0.0, 1.0, _cw)
	Busker.two_bone(sk, "Right", mid - Vector3(gap, 0, 0), sk.get_bone_global_pose(sk.find_bone("RightArm")).origin + Vector3(-0.3, -0.35, -0.05) * u, w)
	Busker.two_bone(sk, "Left", mid + Vector3(gap, 0, 0), sk.get_bone_global_pose(sk.find_bone("LeftArm")).origin + Vector3(0.3, -0.35, -0.05) * u, w)
