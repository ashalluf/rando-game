class_name StreetVendor
extends Pedestrian
## The person working a stand (StreetVendors): at the cart on its kerb side, at the flowers, or
## in a taco truck's window on the truck's floor. A crowd rig like anyone, so shot, knocked, bled
## and ragdolled the same way, in the crowd cap and the "pedestrian" group (they hear gunfire and
## witness crimes). They play the crowd's standing clips (CrowdLife): idle, folded arms, and the
## talking clip when somebody is waiting at their queue, looking at that customer.
##
## Gunfire sends a cart vendor running like everyone else, and when it is over they walk back to
## their stand. The cook in a truck ducks below the counter instead and comes back up after.

## Seconds a truck's cook stays down after a scare, and how far down (m).
@export var duck_seconds: Vector2 = Vector2(4.0, 8.0)
@export var duck_depth: float = 0.85

var home := Vector2.ZERO
var home_yaw: float = 0.0
var in_truck: bool = false
## Metres the floor they stand on is above the pavement (a truck's).
var lift: float = 0.0
var _duck_left: float = 0.0
var _duck_w: float = 0.0
var _beat: float = 0.0


func setup_vendor(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float, truck: bool, floor_y: float) -> void:
	setup(block_rect, 4.0, seed_value)
	home = at
	home_yaw = yaw
	in_truck = truck
	lift = floor_y


## Vendors get the crowd's life clips (Pedestrian only gives them to the plain crowd).
func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_carry = CrowdLife.Carry.NONE
	_jogger = false
	_dog_walker = false


func _ready() -> void:
	super()
	if in_truck:
		# Inside the truck's collision: placed, never solved against it (from the first tick).
		_kinematic = true
		collision_mask = 0
	_work(true)


## At the stand: standing there for good (until something frightens them).
func _work(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 3.0
	_life_base = CrowdLife.IDLE if _life_ok else ""
	if at_once or in_truck:
		_place_at(home, home_yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_stage = Stage.GOING
		_go_to(home)


func _ground_y(x: float, z: float, fallback: float) -> float:
	return super(x, z, fallback) + (lift if in_truck else 0.0)


## Nobody walks a vendor off: out of range they just stay at the stand.
func _life_range_changed(_near: bool) -> void:
	pass


func _update_lod() -> void:
	super()
	if in_truck:
		# Inside the truck's collision: placed, never solved against it.
		_kinematic = true
		collision_mask = 0


func _scare(at: Vector3) -> void:
	if not in_truck:
		super(at)
		return
	_duck_left = _rng.randf_range(duck_seconds.x, duck_seconds.y)
	_look_threat = at
	_look_hold = look_threat_seconds


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	if in_truck:
		_duck_left = maxf(_duck_left - delta, 0.0)
		_duck_w = move_toward(_duck_w, 1.0 if _duck_left > 0.0 else 0.0, delta * 3.0)
		if _visual:
			_visual.position.y = -duck_depth * _duck_w
		return
	# The scare is over and they are walking about: back to the stand.
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE:
		_work(false)


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(3.0, 7.0)
	# Somebody waiting: talk to them (taking the order), else stand about.
	var customer := _customer()
	if customer != null:
		_life_look = customer.global_position + Vector3.UP * 1.5
		if _one_shot_left <= 0.0:
			_life_base = CrowdLife.TALK if _life.randf() < 0.65 else CrowdLife.IDLE
			_life_clip = _life_base
	else:
		_life_look = Vector3.INF
		if _one_shot_left <= 0.0:
			_life_base = CrowdLife.IDLE if _life.randf() < 0.75 or in_truck else CrowdLife.FOLD
			_life_clip = _life_base


## The nearest person waiting at this chunk's queue spots within a few metres.
func _customer() -> Node3D:
	var chunk := get_parent()
	if chunk == null or not chunk.has_meta("vendor_queue"):
		return null
	var here := Vector2(position.x, position.z)
	var best: Node3D = null
	var best_d := 6.0 * 6.0
	for q: Dictionary in chunk.get_meta("vendor_queue"):
		var who: Variant = q.taken
		if who == null or not is_instance_valid(who):
			continue
		var d := (q.p as Vector2).distance_squared_to(here)
		if d < best_d:
			best_d = d
			best = who
	return best
