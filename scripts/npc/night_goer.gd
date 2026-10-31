class_name NightGoer
extends Pedestrian
## Somebody at a venue after dark (NightLife): in the LINE along the wall (standing on the crowd's
## life clips - the phone, texting, talking to the next in line, arms folded - shuffling up a
## place each time the door lets the head in), the BOUNCER at the rope's gap (black, broad,
## arms folded, watching the line and the player), a SMOKER outside a bar, or a FAN behind a
## premiere's barriers (phone out, cheering now and then). A crowd rig like anyone, so shot,
## knocked, bled and ragdolled the same way, in the crowd cap and the "pedestrian" group (they hear
## gunfire and witness crimes).
##
## The line is a loop, so nobody is made or freed: the head goes in at the door and is hidden
## (no body, no hit zone) for INSIDE_SECONDS, then comes out - to a car pulled up for them
## (NightPickups: they walk to its kerb side and get in, hidden until it has gone) or back
## round the corner to the line's tail. Gunfire breaks the line (they run like everyone else,
## and come back to the tail when it is over); the bouncer holds his ground.

enum Role { QUEUE, BOUNCER, SMOKER, FAN }
enum State { LINE, GOING_IN, INSIDE, TO_CAR, IN_CAR, BACK }

## A bouncer's build over the crowd's (width) and how close the player must be to be watched.
@export var bouncer_build: float = 1.12
@export var watch_range: float = 9.0
## Seconds between a person in line changing what they do.
@export var beat_seconds: Vector2 = Vector2(3.0, 8.0)

var role: int = Role.QUEUE
var venue: Dictionary = {}
var home := Vector2.ZERO
var home_yaw: float = 0.0
var state: int = State.LINE
var _beat: float = 0.0
var _until: float = 0.0
var _car: Vehicle = null
var _hidden: bool = false


func setup_role(r: int, block_rect: Rect2, seed_value: int, v: Dictionary, at: Vector2, yaw: float) -> void:
	setup(block_rect, 4.0, seed_value)
	role = r
	venue = v
	home = at
	home_yaw = yaw
	if r == Role.BOUNCER:
		accessory_chance = 0.0


## They get the crowd's life clips (Pedestrian only gives them to the plain crowd).
func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	match role:
		Role.BOUNCER:
			_carry = CrowdLife.Carry.NONE
		Role.SMOKER:
			_carry = CrowdLife.Carry.SMOKE
		Role.FAN:
			_carry = CrowdLife.Carry.TEXT if _life.randf() < 0.55 else CrowdLife.Carry.NONE
		_:
			# A night out: a phone in the hand, a cigarette now and then, never a coffee or shopping.
			if _carry == CrowdLife.Carry.CUP or _carry == CrowdLife.Carry.BAG:
				_carry = CrowdLife.Carry.TEXT if _life.randf() < 0.5 else CrowdLife.Carry.NONE


func _add_model() -> bool:
	if not super._add_model():
		return false
	if role != Role.BOUNCER:
		return true
	_visual.scale = Vector3(_visual.scale.x * bouncer_build, _visual.scale.y * 1.03, _visual.scale.z * bouncer_build)
	var inst: Node3D = null
	for c in _visual.get_children():
		if c is Node3D:
			inst = c
			break
	if inst == null:
		return true
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			var mat := ParkletDiner.waiter_material(src.albedo_texture)
			if mat:
				mi.material_override = mat
	return true


func _ready() -> void:
	super()
	_kinematic = true
	collision_mask = 0
	if role == Role.QUEUE and not venue.is_empty():
		(venue.members as Array).append(self)
		if int(venue.admit_ms) == 0:
			venue.admit_ms = _life_now_ms() + int(float(venue.period) * 1000.0 * (0.4 + 0.6 * _life.randf()))
	_stand_at(home, home_yaw, true)


## Standing at `spot` facing `yaw` for good (walking there first unless `at_once`).
func _stand_at(spot: Vector2, yaw: float, at_once: bool) -> void:
	_act = CrowdLife.Act.STAND
	_act_left = INF
	_act_beat = INF
	_act_spot = spot
	_act_face = yaw
	_life_look = Vector3.INF
	_life_base = _pick_base() if _life_ok else ""
	_beat = _life.randf_range(0.5, beat_seconds.y)
	if at_once:
		_place_at(spot, yaw)
		_stage = Stage.DOING
		_life_clip = _life_base
	else:
		_life_clip = ""
		_stage = Stage.GOING
		_target = spot
		_route = PackedVector2Array()
		_route_pending = false


func _pick_base() -> String:
	match role:
		Role.BOUNCER:
			return CrowdLife.FOLD if _life.randf() < 0.7 else CrowdLife.IDLE
		Role.SMOKER:
			return CrowdLife.TALK if _life.randf() < 0.4 else CrowdLife.IDLE
		Role.FAN:
			return CrowdLife.IDLE if _carry == CrowdLife.Carry.TEXT or _life.randf() < 0.6 else CrowdLife.TALK
	var r := _life.randf()
	if _carry == CrowdLife.Carry.CALL or (_carry == CrowdLife.Carry.TEXT and r < 0.3):
		return CrowdLife.PHONE
	if r < 0.55:
		return CrowdLife.TALK
	if r < 0.75:
		return CrowdLife.FOLD
	return CrowdLife.IDLE


## Nobody walks them off: out of range they stay where they are.
func _life_range_changed(_near: bool) -> void:
	pass


func _update_lod() -> void:
	super()
	if _panic_left <= 0.0:
		# On the pavement where they were put: placed, never solved against the world.
		_kinematic = true
		collision_mask = 0


func _scare(at: Vector3) -> void:
	if _hidden:
		return
	if role == Role.BOUNCER:
		# He holds the door: turns to look, does not run.
		_look_threat = at
		_look_hold = look_threat_seconds
		return
	_leave_line()
	super(at)


func _leave_line() -> void:
	if venue.is_empty():
		return
	var members: Array = venue.members
	var i := members.find(self)
	if i >= 0:
		members.remove_at(i)
		_reslot()


## Everybody still in the line takes their place by their order in it (a shuffle up).
func _reslot() -> void:
	var members: Array = venue.members
	for k in range(members.size() - 1, -1, -1):
		if not is_instance_valid(members[k]) or (members[k] as Pedestrian)._down:
			members.remove_at(k)
	for k in members.size():
		var m := members[k] as NightGoer
		if m.state != State.LINE:
			continue
		var s := NightLife.slot_spot(venue, k)
		if (s[0] as Vector2).distance_to(m._act_spot) > 0.05:
			m._stand_at(s[0], float(s[1]), false)


func _physics_process(delta: float) -> void:
	super(delta)
	if _down:
		return
	if not venue.is_empty() and role == Role.QUEUE:
		_line_tick(delta)
	# The scare is over and they are walking about: back to their place (a line's tail).
	if _act == CrowdLife.Act.NONE and _panic_left <= 0.0 and _cross == Cross.NONE and not _hidden:
		if role == Role.QUEUE and not venue.is_empty():
			_join_tail()
		else:
			_stand_at(home, home_yaw, false)


func _line_tick(_delta: float) -> void:
	var now_s := float(_life_now_ms()) * 0.001
	match state:
		State.LINE:
			var members: Array = venue.members
			if not members.is_empty() and members[0] == self and _stage == Stage.DOING and bool(venue.get("open", false)) \
					and _life_now_ms() >= int(venue.admit_ms):
				venue.admit_ms = _life_now_ms() + int(float(venue.period) * 1000.0 * _life.randf_range(0.6, 1.4))
				members.remove_at(0)
				state = State.GOING_IN
				var door: Vector2 = venue.door
				_stand_at(door + (venue.out as Vector2) * 0.25, atan2((venue.out as Vector2).x, (venue.out as Vector2).y), false)
				_reslot()
		State.GOING_IN:
			if _stage == Stage.DOING:
				_hide()
				state = State.INSIDE
				_until = now_s + _life.randf_range(NightLife.INSIDE_SECONDS.x, NightLife.INSIDE_SECONDS.y)
				(venue.inside as Array).append(self)
		State.INSIDE:
			if now_s >= _until:
				(venue.inside as Array).erase(self)
				_come_back()
		State.TO_CAR:
			if not is_instance_valid(_car) or not _car.traffic.has("dp_at"):
				# The car gave up on them: back to the line.
				_car = null
				_show_at(_door_out())
				_join_tail()
			elif _stage == Stage.DOING:
				_hide()
				state = State.IN_CAR
		State.IN_CAR:
			if not is_instance_valid(_car) or not _car.traffic.has("dp_at") or _car.traffic.is_empty():
				# Gone with the car; back later, round the corner, as somebody new.
				_car = null
				state = State.INSIDE
				_until = now_s + _life.randf_range(NightLife.INSIDE_SECONDS.x, NightLife.INSIDE_SECONDS.y)


## Out of the door (or round the corner) and to the line's tail.
func _come_back() -> void:
	var along: Vector2 = venue.along
	var out: Vector2 = venue.out
	var from := (venue.door as Vector2) + along * (float(venue.run) + 4.0) + out * 1.3
	from = _clamp_pavement(from)
	_show_at(from)
	_join_tail()


func _door_out() -> Vector2:
	return (venue.door as Vector2) + (venue.out as Vector2) * 0.5


func _clamp_pavement(p: Vector2) -> Vector2:
	var r := ring
	if r.size.x <= 0.0:
		return p
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


func _join_tail() -> void:
	var members: Array = venue.members
	if not members.has(self):
		members.append(self)
	state = State.LINE
	var k := members.find(self)
	var s := NightLife.slot_spot(venue, mini(k, NightLife.line_room(venue) - 1))
	_stand_at(s[0], float(s[1]), false)


## NightPickups: out of the door and over the pavement to the kerb side of `car`.
func go_to_car(car: Vehicle, kerb_point: Vector2) -> void:
	(venue.inside as Array).erase(self)
	_car = car
	state = State.TO_CAR
	_show_at(_door_out())
	var d := kerb_point - _door_out()
	_stand_at(kerb_point, atan2(-d.x, -d.y), false)


func is_inside() -> bool:
	return state == State.INSIDE and _hidden


func _hide() -> void:
	_hidden = true
	visible = false
	collision_layer = 0
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = false
	_speed = 0.0
	velocity = Vector3.ZERO
	_life_clip = ""


func _show_at(at: Vector2) -> void:
	_hidden = false
	position = Vector3(at.x, _ground_y(at.x, at.y, position.y), at.y)
	_faced = true
	_speed = 0.0
	_panic_left = 0.0
	_pause_left = 0.0
	visible = true
	collision_layer = 8
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = true


func _do_act(delta: float) -> void:
	super(delta)
	if _stage != Stage.DOING or not _life_ok or _hidden:
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(beat_seconds.x, beat_seconds.y)
	if role == Role.BOUNCER:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and player.global_position.distance_to(global_position) < watch_range:
			_life_look = player.global_position + Vector3.UP * 1.5
		else:
			_life_look = _neighbour_look()
		if _one_shot_left <= 0.0 and _life.randf() < 0.25:
			_one_shot(CrowdLife.SHAKE if _life.randf() < 0.4 else CrowdLife.NOD)
		return
	if role == Role.FAN and _one_shot_left <= 0.0 and _life.randf() < 0.3:
		# A cheer at whoever is on the carpet.
		_one_shot(CrowdLife.NOD)
		return
	if _one_shot_left <= 0.0:
		var base := _pick_base()
		if base != _life_base:
			_life_base = base
			_life_clip = base
	_life_look = _neighbour_look() if _life_base == CrowdLife.TALK else Vector3.INF
	if _carry == CrowdLife.Carry.SMOKE and _one_shot_left <= 0.0 and _life.randf() < 0.4:
		_one_shot(CrowdLife.DRINK)


## The head of the next person along (in the line: the one behind or ahead), for talking.
func _neighbour_look() -> Vector3:
	if venue.is_empty():
		return Vector3.INF
	var members: Array = venue.members
	var k := members.find(self)
	for j in [k + 1, k - 1]:
		if j >= 0 and j < members.size() and is_instance_valid(members[j]):
			return (members[j] as Node3D).global_position + Vector3.UP * 1.55
	return Vector3.INF
