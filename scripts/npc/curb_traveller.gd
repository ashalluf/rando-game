class_name CurbTraveller
extends Pedestrian
## A traveller on the terminal's departures kerb (TerminalCurb): standing with their luggage (the
## bags are TerminalCurb's, at their feet) in a group of one to four - on the phone, texting,
## talking to the others, arms folded, a coffee. A crowd rig like anyone, so shot, knocked, bled
## and ragdolled the same way, in the crowd cap and the "pedestrian" group. Gunfire sends them
## running like everyone else (the bags stay where they were); when it is over they walk back.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

var home := Vector2.ZERO
var home_yaw: float = 0.0
## The middle of their group (they look at it while talking).
var group := Vector2.ZERO
var _beat: float = 0.0


func setup_traveller(rect: Rect2, seed_value: int, at: Vector2, yaw: float, centre: Vector2) -> void:
	setup(rect, 4.0, seed_value)
	home = at
	home_yaw = yaw
	group = centre


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	# Travellers: the phone more than anyone, a coffee, never shopping or a cigarette by the doors.
	var r := _life.randf()
	if r < 0.22:
		_carry = CrowdLife.Carry.CALL
	elif r < 0.45:
		_carry = CrowdLife.Carry.TEXT
	elif r < 0.6:
		_carry = CrowdLife.Carry.CUP
	else:
		_carry = CrowdLife.Carry.NONE


func _ready() -> void:
	super()
	_stand(true)


func _stand(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 3.0
	_life_base = _pick_base() if _life_ok else ""
	_beat = _life.randf_range(0.5, 6.0)
	if at_once:
		_place_at(home, home_yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(home)


func _pick_base() -> String:
	var r := _life.randf()
	if _carry == CrowdLife.Carry.CALL or (_carry == CrowdLife.Carry.TEXT and r < 0.6):
		return CrowdLife.PHONE
	if group.distance_to(home) > 0.2 and r < 0.6:
		return CrowdLife.TALK
	if r < 0.8:
		return CrowdLife.IDLE
	return CrowdLife.FOLD


## Nobody walks them off: out of range they stay with their bags.
func _life_range_changed(_near: bool) -> void:
	pass


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	# The scare is over and they are walking about: back to the bags.
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE:
		_stand(false)


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(4.0, 9.0)
	if _one_shot_left <= 0.0:
		var base := _pick_base()
		if base != _life_base:
			_life_base = base
			_life_clip = base
	if _life_base == CrowdLife.TALK:
		_life_look = _world(Vector3(group.x, position.y + 1.55, group.y))
	elif _life_base != CrowdLife.PHONE and _life.randf() < 0.35:
		# A glance down the lanes for their ride.
		_life_look = _world(Vector3(home.x + (_life.randf() - 0.5) * 30.0, position.y + 1.4, home.y - 12.0))
	else:
		_life_look = Vector3.INF


## A point in the chunk's space (true world) as a global one (after any origin shift).
func _world(local: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	return parent.to_global(local) if parent else local
