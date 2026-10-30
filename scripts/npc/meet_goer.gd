class_name MeetGoer
extends Pedestrian
## Somebody at a lowrider meet (LowriderMeet): stands on the pavement by the row of cars, looks
## at the car beside them - or whichever one nearby is hopping or three-wheeling - talks with the
## people round them, and now and then holds a phone up filming. A crowd rig like anyone (shot,
## knocked, ragdolled, in the crowd cap, hears gunfire), and when the scare is over they walk
## back to their spot.

var home := Vector2.ZERO
var home_yaw: float = 0.0
## Which way the road runs (CityPlan.AXIS_*), to look along the row.
var road_axis: int = 0
var _beat: float = 0.0
var _show_car: Node3D


func setup_goer(block_rect: Rect2, seed_value: int, at: Vector2, yaw: float, axis: int) -> void:
	setup(block_rect, 4.0, seed_value)
	home = at
	home_yaw = yaw
	road_axis = axis


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	# A third have their phone out (texting is the hands-in-front pose: filming the show).
	_carry = CrowdLife.Carry.TEXT if _life.randf() < 0.3 else (CrowdLife.Carry.CUP if _life.randf() < 0.2 else CrowdLife.Carry.NONE)


func _ready() -> void:
	super()
	_stand(true)


func _stand(at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_face = home_yaw
	_act_beat = 2.0
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


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE:
		_stand(false)


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok:
		return
	_beat -= delta
	# Whatever is putting on a show within reach takes everybody's eyes.
	if _show_car != null and is_instance_valid(_show_car):
		_life_look = _show_car.global_position + Vector3.UP * 0.9
	if _beat > 0.0:
		return
	_beat = _life.randf_range(1.5, 4.0)
	_show_car = _performing_car()
	if _show_car != null:
		_life_look = _show_car.global_position + Vector3.UP * 0.9
		if _one_shot_left <= 0.0:
			_life_base = CrowdLife.IDLE if _carry == CrowdLife.Carry.TEXT else (CrowdLife.TALK if _life.randf() < 0.35 else CrowdLife.IDLE)
			_life_clip = _life_base
	else:
		_life_look = Vector3.INF
		if _one_shot_left <= 0.0:
			var r := _life.randf()
			_life_base = CrowdLife.TALK if r < 0.45 else (CrowdLife.FOLD if r < 0.65 else CrowdLife.IDLE)
			_life_clip = _life_base


## The nearest lowrider within 18 m whose hydraulics are at work, or null.
func _performing_car() -> Node3D:
	var best: Node3D = null
	var best_d := 18.0 * 18.0
	for car in get_tree().get_nodes_in_group("lowrider_meet"):
		var h := (car as Node).get_node_or_null("Hydraulics")
		if h == null or String(h.call("routine")) == "":
			continue
		var d := (car as Node3D).global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = car
	return best
