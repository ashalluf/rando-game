class_name Worshipper
extends Pedestrian
## One of a congregation (WorshipSunday): an ordinary pedestrian - shot, knocked, bled and
## ragdolled like anyone, in the crowd cap, living the crowd-life layer - in Sunday clothes (a
## suit, a blazer, a dress, a button shirt: WorshipSunday.BEST), kept to the site instead of a
## block's pavement ring.
##
## ARRIVE: along the pavement to the gate, up the path, a while on the forecourt (talking, waiting
## for the doors), then in at the door - hidden inside, collision off - and back out of view along
## the pavement a few minutes later to walk in again (the arrivals keep coming while the bell is
## due). GATHER: on the forecourt, standing in groups and talking, now and then drifting to
## another spot; after a service everybody is a GATHER and a share wander out to the street.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

enum Role { ARRIVE, GATHER }

var role: int = Role.ARRIVE
## The site's points in the chunk's space (WorshipSunday.spots(), moved into the chunk).
var pts: Dictionary = {}
## Where along the arrival this person is: 0 the street, 1 the gate, 2 the path, 3 the forecourt,
## 4 the door.
var leg: int = 0
var leaving: bool = false
var _inside: float = 0.0
var _side: float = 1.0
## The site's kind and seed (WorshipSunday.busy(): whether there is still a reason to be here).
var kind: int = 0
var site_seed: int = 0


func setup_worship(block_rect: Rect2, seed_value: int, points: Dictionary, r: int, start: float, after: bool) -> void:
	pts = points
	role = r
	leaving = after
	_side = -1.0 if Worship.h01([seed_value, "ws_side"]) < 0.5 else 1.0
	# The arrivals spread along the route: on the pavement, at the gate, up the path, already in.
	leg = clampi(int(start * 4.0), 0, 3) if role == Role.ARRIVE else 3
	var best: Array = WorshipSunday.BEST
	model_pick = "res://assets/models/%s.glb" % best[absi(hash([seed_value, "ws_model"])) % best.size()]
	setup(block_rect, 4.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.3
	pause_seconds = Vector2(2.0, 5.0)
	life_chance = 0.9 if role == Role.GATHER else 0.45
	life_spawn_chance = 0.85 if role == Role.GATHER else 0.25
	walk_speed *= 0.85
	_speed = walk_speed
	add_to_group("worshipper")


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	var r := _life.randf()
	_carry = CrowdLife.Carry.BAG if r < 0.18 else CrowdLife.Carry.NONE


## Where this person is put when the chunk builds them: along their leg of the route.
func start_point() -> Vector2:
	if pts.is_empty():
		return Vector2(position.x, position.z)
	var j := Worship.h01([_life_seed, "ws_j"])
	match leg:
		0:
			var st: Array = pts.street
			var a: Vector2 = st[0] if _side < 0.0 else st[1]
			return a.lerp(pts.gate_out, 0.25 + 0.7 * j)
		1:
			return (pts.gate_out as Vector2).lerp(pts.gate_in, j)
		2:
			return (pts.gate_in as Vector2).lerp(pts.door, 0.2 + 0.6 * j)
	return _court_spot()


func _court_spot() -> Vector2:
	var c: Array = pts.get("court", [])
	if c.is_empty():
		return Vector2(position.x, position.z)
	return c[_rng.randi() % c.size()] + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))


## Whether the site is still busy (on its day, before or after a service) at this hour.
func _still_busy() -> bool:
	if not is_inside_tree():
		return true
	return WorshipSunday.busy(kind, site_seed, WorshipSunday.day_now(self), WorshipSunday.hour_now(self)) > 0.02


## The next stop on the route.
func _random_ring_point(sidewalk: float) -> Vector2:
	if pts.is_empty():
		return super(sidewalk)
	if not leaving and leg >= 3 and not _still_busy():
		# The service is over (or the doors long shut): out by the gate and home.
		leaving = true
		leg = 10
	if leaving:
		# After the service: on the forecourt a while, then out by the gate and along the street,
		# and gone (back for the next service as an arrival).
		if leg == 3 and _rng.randf() < 0.75:
			return _court_spot()
		leg = maxi(leg, 10) + 1
		match leg:
			11:
				return pts.gate_in
			12:
				return pts.gate_out
			13:
				var st: Array = pts.street
				return st[0] if _side < 0.0 else st[1]
		leaving = false
		role = Role.ARRIVE
		_go_inside()
		return Vector2(position.x, position.z)
	if role == Role.GATHER:
		return _court_spot()
	leg += 1
	match leg:
		1:
			return pts.gate_out
		2:
			return pts.gate_in
		3:
			return _court_spot()
		4:
			# A share stand longer outside; the rest go in.
			if _rng.randf() < 0.35:
				leg = 3
				return _court_spot()
			return pts.door
	# At the door: in.
	_go_inside()
	return Vector2(position.x, position.z)


## Talk on the forecourt or wait there; never a bus, a shop, a cart.
func _try_life(at_spawn: bool) -> bool:
	if not _life_free() or leg != 3:
		return false
	if _life.randf() < 0.65 and _plan_talk(at_spawn):
		return true
	return _start_stand(_life.randf_range(stand_seconds.x, stand_seconds.y))


## The site is open ground: walk straight there.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	if pts.is_empty():
		return super(_from, _to)
	return PackedVector2Array()


func _go_inside() -> void:
	_inside = _rng.randf_range(90.0, 240.0)
	visible = false
	collision_layer = 0
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = false
	_speed = 0.0
	velocity = Vector3.ZERO


func _come_back() -> void:
	_inside = 0.0
	if not _still_busy():
		# Nothing on here now: they have gone home (their room in the crowd cap with them).
		queue_free()
		return
	leg = 0
	var st: Array = pts.street
	var a: Vector2 = st[0] if _side < 0.0 else st[1]
	position = Vector3(a.x, _ground_y(a.x, a.y, position.y), a.y)
	visible = true
	collision_layer = 8
	var area := _hit_shape.get_parent() as Area3D if _hit_shape else null
	if area:
		area.monitoring = true
	_go_to(_random_ring_point(_sidewalk))


func _physics_process(delta: float) -> void:
	if _inside > 0.0:
		_inside -= delta
		if _inside <= 0.0:
			_come_back()
		return
	super(delta)
